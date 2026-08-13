"""
AIOps Incident RAG & Telemetry Anomaly Analysis Pipeline Example
Includes Financial Data Masking (PII Anonymization) & Private LLM Gateway integration.
"""

import re
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("AIOps-RAG-Pipeline")

class FinancialDataAnonymizer:
    """금융 데이터 비식별화 및 PII 마스킹 필터

    이 클래스를 통과한 텍스트만 프라이빗 LLM 게이트웨이로 나간다. 즉 여기서 놓친
    패턴은 그대로 외부 추론 요청에 실려 나가므로, 마스킹 누락은 곧 유출이다.
    패턴을 손볼 때는 반드시 contexts/aiops/tests/run.sh 의 회귀 케이스로 검증할 것.
    """

    # 주민등록번호. 뒷자리 첫 숫자는 내국인 1-4 외에 외국인 5-8, 1800년대생 9-0 이 있어
    # [1-4] 로 좁히면 그 대상이 이 패턴에서 빠진다. 빠진 값이 CARD_PATTERN 에 우연히
    # 걸려 마스킹되더라도 라벨이 어긋나 감사 추적이 틀어지므로 처음부터 전부 받는다.
    RRN_PATTERN = re.compile(r'\b\d{6}-[0-9]\d{6}\b')

    # 카드번호. 구분자로 하이픈·공백뿐 아니라 점(.)도 실제로 쓰인다. [ -] 로만 두면
    # 1234.5678.9012.3456 형태가 통째로 마스킹되지 않고 빠져나간다(실측 확인).
    #
    # 앞뒤 경계에 숫자·점이 붙어 있으면 매치하지 않는다. \b 는 숫자와 점 사이를 경계로
    # 인정하기 때문에, 이 가드가 없으면 더 긴 숫자열의 앞부분만 잘라 카드로 오인한다
    # (실측: "peers: 192.168.10.11 192.168.10.12" -> "[MASKED_CARD_NUMBER].168.10.12" —
    # IP 나열이 카드로 마스킹되면서 로그가 의미 불명으로 훼손됐다).
    # 하이픈은 일부러 제외하지 않는다. 제외하면 "card-1234-5678-9012-3456" 처럼 키 이름에
    # 하이픈으로 이어 붙인 실제 카드번호가 검출망에서 빠져 유출 방향으로 뒤집힌다.
    CARD_PATTERN = re.compile(r'(?<![\d.])(?:\d[ .-]*?){13,16}(?![\d.])')

    # 계좌번호는 하이픈으로 끊긴 3개 그룹이 전부다. 앞뒤에 하이픈+숫자가 더 붙어 있다면
    # 그건 계좌가 아니라 더 긴 번호(카드 등)의 일부이므로 매치에서 뺀다. 이 가드가 있어야
    # CARD 보다 먼저 돌려도 카드번호의 앞 세 그룹(1234-5678-9012)을 계좌로 가로채지 않는다.
    ACCOUNT_PATTERN = re.compile(r'(?<![\d.-])\d{3,6}-\d{2,6}-\d{3,6}(?![\d.-])')

    # 휴대전화/유선번호. 계좌 형식(3-4-4 등)과 모양이 겹쳐 ACCOUNT_PATTERN 이 먼저 삼키면
    # 전화번호가 [MASKED_ACCOUNT_NUMBER] 로 기록돼 감사 추적이 틀어진다(실측: 010-1234-5678).
    # 탐지 범위를 좁히는 변경이 아니라 라벨을 바로잡기 위해 추가한 패턴이다.
    PHONE_PATTERN = re.compile(r'(?<![\d.-])(?:01[016789]|02|0[3-6]\d)-\d{3,4}-\d{4}(?![\d.-])')

    # 이메일 주소도 개인정보보호법상 개인정보다. 금융 로그에는 고객 이메일이 흔히
    # 섞여 들어오는데 위 세 패턴 중 어느 것도 이를 잡지 못했다.
    EMAIL_PATTERN = re.compile(r'\b[\w.+-]+@[\w-]+\.[\w.-]+\b')

    @classmethod
    def sanitize(cls, text: str) -> str:
        # 순서 주의: 더 구체적인 패턴(주민번호)을 먼저 지워야 한다. 카드번호 패턴은
        # 자릿수만 보므로 13자리인 주민번호를 카드로 먼저 삼켜 라벨이 뒤바뀐다.
        #
        # 같은 이유로 전화번호·계좌번호를 카드번호보다 먼저 지운다. CARD_PATTERN 은 자릿수만
        # 보므로 13자리 이상 계좌(예: 1002-123-456789)를 카드로 먼저 삼켰다(실측). 두 패턴은
        # 위에서 앞뒤 하이픈+숫자를 배제하도록 고정해 뒀으므로, 먼저 돌아도 카드번호의 앞
        # 세 그룹을 가로채지 않는다 — 즉 탐지 범위는 그대로 두고 라벨만 정확해진다.
        text = cls.RRN_PATTERN.sub("[MASKED_RRN]", text)
        text = cls.EMAIL_PATTERN.sub("[MASKED_EMAIL]", text)
        text = cls.PHONE_PATTERN.sub("[MASKED_PHONE_NUMBER]", text)
        text = cls.ACCOUNT_PATTERN.sub("[MASKED_ACCOUNT_NUMBER]", text)
        text = cls.CARD_PATTERN.sub("[MASKED_CARD_NUMBER]", text)
        return text

class IncidentRAGPipeline:
    """이종 텔레메트리 수집 및 프라이빗 LLM RAG 기반 RCA 진단 파이프라인"""
    def __init__(self, private_llm_gateway_url: str):
        self.gateway_url = private_llm_gateway_url

    def analyze_incident(self, metric_data: dict, log_snippet: str, trace_id: str) -> dict:
        # 1. PII 및 금융 민감 데이터 마스킹
        clean_log = FinancialDataAnonymizer.sanitize(log_snippet)
        
        # 2. 이종 데이터 통합 컨텍스트 구성
        prompt_payload = {
            "trace_id": trace_id,
            "metrics": metric_data,
            "sanitized_logs": clean_log,
            "instruction": (
                "분석 시 개인 추정을 배제하고 수집된 팩트 데이터와 사내 런북에만 기반(Grounding)하여 "
                "근원 원인(RCA) 및 복구 액션 아이템을 제시하십시오."
            )
        }
        
        logger.info(f"[AIOps-Agent-Action] RCA Prompt generated for Trace ID: {trace_id}")
        return prompt_payload

if __name__ == "__main__":
    pipeline = IncidentRAGPipeline(private_llm_gateway_url="https://ai-gateway.internal.bank/v1")
    sample_log = "Error during transfer for account 123-45-67890, RRN 900101-1234567. Connection timed out."
    result = pipeline.analyze_incident(
        metric_data={"cpu_utilization": 98.4, "db_connection_pool": 0},
        log_snippet=sample_log,
        trace_id="trace-abc-123-456"
    )
    print("Sanitized Prompt Payload:", result)

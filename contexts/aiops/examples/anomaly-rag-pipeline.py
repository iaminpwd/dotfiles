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
    CARD_PATTERN = re.compile(r'\b(?:\d[ .-]*?){13,16}\b')

    ACCOUNT_PATTERN = re.compile(r'\b\d{3,6}-\d{2,6}-\d{3,6}\b')

    # 이메일 주소도 개인정보보호법상 개인정보다. 금융 로그에는 고객 이메일이 흔히
    # 섞여 들어오는데 위 세 패턴 중 어느 것도 이를 잡지 못했다.
    EMAIL_PATTERN = re.compile(r'\b[\w.+-]+@[\w-]+\.[\w.-]+\b')

    @classmethod
    def sanitize(cls, text: str) -> str:
        # 순서 주의: 더 구체적인 패턴(주민번호)을 먼저 지워야 한다. 카드번호 패턴은
        # 자릿수만 보므로 13자리인 주민번호를 카드로 먼저 삼켜 라벨이 뒤바뀐다.
        text = cls.RRN_PATTERN.sub("[MASKED_RRN]", text)
        text = cls.EMAIL_PATTERN.sub("[MASKED_EMAIL]", text)
        text = cls.CARD_PATTERN.sub("[MASKED_CARD_NUMBER]", text)
        text = cls.ACCOUNT_PATTERN.sub("[MASKED_ACCOUNT_NUMBER]", text)
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

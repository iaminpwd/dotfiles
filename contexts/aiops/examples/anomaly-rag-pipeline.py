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
    #
    # (?<![A-Za-z]) 는 UUID 훼손을 막는다. 위 IP 나열과 정확히 같은 실패 모드인데 경계
    # 가드가 숫자·점만 봐서 걸러지지 않았다(실측:
    # "req 550e8400-e29b-41d4-a716-446655440000 ok"
    #  -> "req 550e8400-e29b-41d4-a[MASKED_CARD_NUMBER] ok").
    # 16진 그룹의 글자 바로 뒤에서 숫자열이 시작되면 그건 UUID·해시의 일부지 카드가 아니다.
    # 글자에 "붙어" 시작하는 경우만 막으므로 "card-1234-..."(앞이 하이픈)나
    # "Card 4111 ..."(앞이 공백)는 그대로 검출된다. UUID 는 이 가드로 시작점이 모두 막힌
    # 뒤 남는 최장 연속 그룹이 12자리라 하한 13 에도 걸리지 않는다.
    CARD_PATTERN = re.compile(r'(?<![\d.])(?<![A-Za-z])(?:\d[ .-]*?){13,16}(?![\d.])')

    # 구분자 없이 이어진 PAN. 위 CARD_PATTERN 은 상한이 16이라 17~19자리를 "부분적으로도"
    # 잡지 못하고 통째로 흘려보냈다(실측: 17/18/19자리 연속 숫자가 원문 그대로 통과).
    # 앞뒤 lookaround 때문에 매치 시작점 자체가 사라지기 때문이다 — 문자열 앞에서 13~16자리를
    # 먹으면 뒤에 숫자가 남아 (?![\d.]) 가 실패하고, 한 칸 뒤부터 시작하면 (?<![\d.]) 가
    # 실패한다. ISO/IEC 7812 은 PAN 을 최대 19자리로 정의하고 Visa/Maestro 등이 실제로
    # 발급하므로 이건 곧 유출이다.
    #
    # 상한만 19로 올리지 않는 이유: 위 패턴은 구분자(공백·점·하이픈)를 자유롭게 허용해서,
    # 범위를 넓히면 "192.168.10.11 192.168.10.12"(숫자 18개)처럼 점·공백으로 이어진 IP
    # 나열이 통째로 카드로 오탐된다. 그 회귀는 tests/run.sh 가 이미 고정해 둔 축이다.
    # 그래서 범위를 넓히는 대신 "구분자가 하나도 없는 연속 숫자"만 따로 받는다 —
    # IP·타임스탬프는 반드시 점/하이픈/콜론으로 끊기므로 이 패턴에 걸리지 않는다.
    CARD_PLAIN_PATTERN = re.compile(r'(?<![\d.])\d{13,19}(?![\d.])')

    # 계좌번호는 하이픈으로 끊긴 3개 그룹이 전부다. 앞뒤에 하이픈+숫자가 더 붙어 있다면
    # 그건 계좌가 아니라 더 긴 번호(카드 등)의 일부이므로 매치에서 뺀다. 이 가드가 있어야
    # CARD 보다 먼저 돌려도 카드번호의 앞 세 그룹(1234-5678-9012)을 계좌로 가로채지 않는다.
    ACCOUNT_PATTERN = re.compile(r'(?<![\d.-])\d{3,6}-\d{2,6}-\d{3,6}(?![\d.-])')

    # 휴대전화/유선번호. 계좌 형식(3-4-4 등)과 모양이 겹쳐 ACCOUNT_PATTERN 이 먼저 삼키면
    # 전화번호가 [MASKED_ACCOUNT_NUMBER] 로 기록돼 감사 추적이 틀어진다(실측: 010-1234-5678).
    # 탐지 범위를 좁히는 변경이 아니라 라벨을 바로잡기 위해 추가한 패턴이다.
    # 하이픈은 선택이다. 필수로 두면 "01012345678" 처럼 붙여 쓴 번호가 어느 패턴에도
    # 걸리지 않아 그대로 나갔다(실측) — 11자리라 CARD_PATTERN 의 하한 13 에도 미달해
    # 카드 쪽으로도 새지 않는다. 이메일을 "개인정보보호법상 개인정보"라며 추가한 것과
    # 같은 기준이 전화번호에만 적용되지 않고 있었다.
    # 국번 접두사(01x/02/0[3-6]x)를 강제하므로 하이픈을 풀어도 임의의 10~11자리 숫자가
    # 전화번호로 오탐되지는 않는다.
    #
    # 국제 표기(+82)를 별도 분기로 받는다. 국제 표기는 앞자리 0을 떼므로 국내 분기의
    # 국번 패턴에 걸리지 않고, 앞의 하이픈 때문에 (?<![\d.-]) 경계도 막혀 어떤 위치에서도
    # 매치가 시작되지 않았다 — 휴대전화 번호 전체가 그대로 게이트웨이로 나갔다(실측:
    # "call +82-10-1234-5678 now" 가 원문 그대로 통과).
    # 두 분기를 합쳐 앞자리 0을 선택으로 만들지는 않는다. 그러면 유닉스 타임스탬프
    # (예: 1755172800 -> 17|5517|2800)처럼 평범한 10자리 숫자가 전화번호로 오탐된다.
    # 구분자로 공백도 받는 것은 이 분기뿐이다("+82 10 1234 5678"가 흔한 표기라서).
    #
    # 앞 경계에서 하이픈을 빼는 이유는 CARD_PATTERN 이 이미 같은 판단을 내려 둔 것과 같다 —
    # 제외하면 "user-010-1234-5678", "trace-01012345678" 처럼 키 이름에 하이픈으로 이어
    # 붙인 실제 번호가 검출망에서 빠져 유출 방향으로 뒤집힌다(실측: 둘 다 원문 그대로 통과.
    # 밑줄로 이은 "id_01012345678" 은 마스킹돼서 하이픈만의 문제임이 드러났다).
    # 뒤 경계에는 하이픈을 남긴다. 앞은 "키 이름이 붙는 자리"라 흘려보내면 유출이지만,
    # 뒤는 더 긴 번호의 앞부분을 잘라 오탐하는 자리이기 때문이다.
    # 카드·계좌를 가로챌 위험은 국번 접두사(01x/02/0[3-6]x) 강제가 막는다 — 카드번호
    # 앞머리(4111, 1002 등)는 이 접두사에 걸리지 않는다.
    PHONE_PATTERN = re.compile(
        r'(?<![\d.])(?:'
        r'\+82[ -]?(?:1[016789]|2|[3-6]\d)[ -]?\d{3,4}[ -]?\d{4}'
        r'|(?:01[016789]|02|0[3-6]\d)-?\d{3,4}-?\d{4}'
        r')(?![\d.-])'
    )

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
        # 연속 PAN 을 구분자형보다 먼저 지운다. 둘 다 같은 라벨이라 순서가 판정을 바꾸지는
        # 않지만, 13~19자리 연속 숫자를 한 번에 확정해 두면 뒤 패턴이 그 일부만 잘라 가는
        # 경우를 구조적으로 배제할 수 있다.
        text = cls.CARD_PLAIN_PATTERN.sub("[MASKED_CARD_NUMBER]", text)
        text = cls.CARD_PATTERN.sub("[MASKED_CARD_NUMBER]", text)
        return text

    @classmethod
    def sanitize_obj(cls, obj):
        """문자열이 어디에 들어 있든(중첩 dict/list 포함) 살균한다.

        sanitize()는 문자열 하나만 받으므로, 게이트웨이로 나가는 payload 에 dict 나 list 로
        실려 나가는 값은 손도 못 댄다. 그런데 이 클래스의 계약은 "여기를 통과한 것만
        나간다"이므로, 자료구조 단위 진입점이 없으면 그 계약이 호출부에서 조용히 깨진다
        (실측: metric_data 에 넣은 이메일·주민번호가 payload 에 원문 그대로 남았다).
        키도 함께 살균한다 — 키 이름에 식별자를 박아 넣는 로그 스키마가 실제로 있다.
        """
        if isinstance(obj, str):
            return cls.sanitize(obj)
        if isinstance(obj, dict):
            return {cls.sanitize_obj(k): cls.sanitize_obj(v) for k, v in obj.items()}
        if isinstance(obj, list):
            return [cls.sanitize_obj(v) for v in obj]
        if isinstance(obj, tuple):
            return tuple(cls.sanitize_obj(v) for v in obj)
        # bool 은 int 의 서브클래스라 아래 숫자 분기보다 먼저 빼낸다. True/False 를
        # 문자열화해도 어떤 패턴에도 걸리지 않지만, 타입을 건드릴 이유가 없다.
        if isinstance(obj, bool):
            return obj
        # 숫자로 실려 나가는 식별자를 막는다. 예전엔 문자열만 살균해서, 같은 값이라도
        # 자료형이 int 면 그대로 나갔다(실측: {"pan": 4111111111111111} 이 payload 에
        # 원문 유지, "4111111111111111" 은 마스킹). JSON 텔레메트리에서 계좌·카드번호가
        # 숫자로 직렬화되는 것은 특수 케이스가 아니라 기본 동작이라, 이 클래스의 계약
        # ("여기를 통과한 것만 나간다")이 자료형 하나로 조용히 우회되고 있었다.
        #
        # [트레이드오프] 13자리 epoch-millis 타임스탬프(예: 1755172800000)가
        # CARD_PLAIN_PATTERN(13~19자리)에 걸려 카드로 마스킹된다. 이를 감수하는 이유는
        # 두 가지다. (1) 오탐은 라벨이 틀릴 뿐이지만 미탐은 곧 유출이고, 이 클래스의
        # 선언이 그 우선순위를 이미 정해 뒀다. (2) 같은 오탐이 문자열 경로에는 이미
        # 존재하므로, 숫자만 예외로 두는 쪽이 오히려 정책의 일관성을 깨뜨린다.
        # 자릿수 대신 Luhn 검사로 좁히는 방법이 있지만 그건 룰북에 없는 정책을 이
        # 스크립트가 임의로 신설하는 것이라(DENYLISTED_LABEL_KEYS 주석의 같은 판단)
        # 채택하지 않는다.
        #
        # 패턴에 걸렸을 때만 문자열로 바꾼다. 안 걸린 값까지 문자열화하면 숫자 메트릭이
        # 전부 문자열이 되어 다운스트림 집계가 깨진다.
        if isinstance(obj, (int, float)):
            as_text = str(obj)
            masked = cls.sanitize(as_text)
            return masked if masked != as_text else obj
        return obj

class IncidentRAGPipeline:
    """이종 텔레메트리 수집 및 프라이빗 LLM RAG 기반 RCA 진단 파이프라인"""
    def __init__(self, private_llm_gateway_url: str):
        self.gateway_url = private_llm_gateway_url

    def analyze_incident(self, metric_data: dict, log_snippet: str, trace_id: str) -> dict:
        # 1. PII 및 금융 민감 데이터 마스킹
        #
        # log_snippet 하나만 살균하면 안 된다. 게이트웨이로 나가는 것은 이 함수가 만드는
        # payload 전체이지 로그 조각 하나가 아니다. 예전엔 metric_data 와 trace_id 가
        # 원문 그대로 실려 나갔고(실측: metric_data 에 넣은 이메일·주민번호와 trace_id 에
        # 섞인 휴대전화 번호가 payload 에 그대로 남음), trace_id 는 아래 logger.info 를
        # 통해 로컬 로그에도 찍혔다 — FinancialDataAnonymizer 의 클래스 주석이 선언한
        # "이 클래스를 통과한 텍스트만 나간다"가 호출부에서 지켜지지 않고 있었다.
        clean_log = FinancialDataAnonymizer.sanitize(log_snippet)
        clean_metrics = FinancialDataAnonymizer.sanitize_obj(metric_data)
        clean_trace_id = FinancialDataAnonymizer.sanitize(trace_id)

        # 2. 이종 데이터 통합 컨텍스트 구성
        prompt_payload = {
            "trace_id": clean_trace_id,
            "metrics": clean_metrics,
            "sanitized_logs": clean_log,
            "instruction": (
                "분석 시 개인 추정을 배제하고 수집된 팩트 데이터와 사내 런북에만 기반(Grounding)하여 "
                "근원 원인(RCA) 및 복구 액션 아이템을 제시하십시오."
            )
        }
        
        logger.info(f"[AIOps-Agent-Action] RCA Prompt generated for Trace ID: {clean_trace_id}")
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

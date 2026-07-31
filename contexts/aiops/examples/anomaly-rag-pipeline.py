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
    """금융 데이터 비식별화 및 PII 마스킹 필터"""
    RRN_PATTERN = re.compile(r'\b\d{6}-[1-4]\d{6}\b')
    CARD_PATTERN = re.compile(r'\b(?:\d[ -]*?){13,16}\b')
    ACCOUNT_PATTERN = re.compile(r'\b\d{3,6}-\d{2,6}-\d{3,6}\b')

    @classmethod
    def sanitize(cls, text: str) -> str:
        text = cls.RRN_PATTERN.sub("[MASKED_RRN]", text)
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

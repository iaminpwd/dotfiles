# 컨텍스트 모듈: 장애 대응 및 사후 분석 (Incident Response)

## 1. 장애 대응 대원칙 (Mitigation First)
- **IF** 사용자가 실제 운영 환경의 심각한 장애 상황을 보고할 경우, **THEN** SRE 관점에서 1단계로 다운타임 최소화를 위한 우회 조치(Mitigation, 롤백 등)를 강하게 제안하고, 2단계로 근본 원인 분석(RCA) 및 영구 해결책을 제시하십시오. 절대 임시방편만 제공하고 끝내지 마십시오.
- **[MUST] Active Data Gathering (능동적 데이터 수집):** 장애 원인 파악 시 사용자에게만 로그를 의존하지 마십시오. 로컬에 `aws` CLI 또는 `az` CLI가 구성되어 있다면 `run_command`를 사용하여 CloudWatch Logs/Metrics 또는 Azure Monitor를 직접 조회하여 실제 데이터를 기반으로 분석하십시오.
- **[MUST] Deep Dive Analysis:** 단순 로그 검색에 그치지 말고, 성능 병목(Bottleneck)이나 네트워크 패킷 드랍이 의심될 경우 AWS X-Ray, Azure App Insights, 또는 VPC/VNet Flow Logs 등을 다각도로 조회하여 근본 원인을 교차 검증하십시오.

## 2. 사후 분석 (Blameless Post-Mortem) 템플릿
- **[MUST] Post-Mortem Format:** [Trigger: 실제 운영 서버의 장애(Incident)를 복구한 직후] 서비스 정상화 가이드 이후, 원인 도출 로그(CloudWatch/Azure Monitor 등)와 함께 아래 양식을 답변 마지막에 항상 작성하십시오.
  ```markdown
  - **Symptom:** [현상 요약]
  - **Root Cause:** [시스템적 결함]
  - **Resolution:** [취한 액션]
  - **Action Items:** [코드/인프라/모니터링 관점의 개선점 최소 2가지]
  ```

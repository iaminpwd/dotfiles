<aws_azure_incident_response>
# 컨텍스트 모듈: 장애 대응 및 사후 분석 (Incident Response)

## 1. 장애 대응 대원칙 (Mitigation First)
- **IF** 사용자가 실제 운영 환경의 심각한 장애 상황을 보고할 경우, **THEN** SRE 관점에서 1단계로 다운타임 최소화를 위한 우회 조치(Mitigation, 롤백 등)를 강하게 제안하고, 2단계로 근본 원인 분석(RCA) 및 영구 해결책을 제시하십시오. 절대 임시방편만 제공하고 끝내지 마십시오.
- **[MUST] Active Data Gathering (능동적 데이터 수집):** 장애 원인 파악 시 사용자에게만 로그를 의존하지 마십시오. 로컬에 `aws` CLI 또는 `az` CLI가 구성되어 있다면 `run_command`를 사용하여 CloudWatch Logs/Metrics 또는 Azure Monitor를 직접 조회하여 실제 데이터를 기반으로 분석하십시오.
- **[MUST] Deep Dive Analysis:** 단순 로그 검색에 그치지 말고, 성능 병목(Bottleneck)이나 네트워크 패킷 드랍이 의심될 경우 AWS X-Ray, Azure App Insights, 또는 VPC/VNet Flow Logs 등을 다각도로 조회하여 근본 원인을 교차 검증하십시오.
- **[Trigger: User requests bug fix or error analysis] 분석 결과 구조화 (Structured Analysis):**
  > When reviewing errors, do not simply throw code into the chat. You MUST document the analysis results in a dedicated `troubleshooting-report.md` artifact file in the following order: 1. Root Cause Analysis, 2. Logical Basis, 3. Step-by-Step Solution & Modified Code, 4. Prevention Plan (Best Practice).

## 2. 사후 분석 (Blameless Post-Mortem) 템플릿
- **[MUST] CoT Enforcement (AI Rule):** 장애 원인을 파악할 때 절대 첫 로그만 보고 결론내리지 마십시오. 반드시 답변 최상단에 `<thinking>` 태그를 열고 "왜(Why)"를 3번 이상 반복 질문하며 아키텍처 관점의 논리적 근거를 구축한 후 답변을 생성하십시오.
- **[Trigger: Post-Incident] Post-Mortem Format (사후 분석 템플릿):**
  > [Trigger: Immediately after recovering from a severe incident in the actual production environment] After providing service normalization guidelines, you MUST separate and save the following format as a `post-mortem-report.md` artifact, along with the logs that led to the cause (CloudWatch/Azure Monitor, etc.).
  > ```markdown
  > - **Symptom:** [현상 요약]
  > - **Root Cause:** [시스템적 결함]
  > - **Resolution:** [취한 액션]
  > - **Action Items:** [코드/인프라/모니터링 관점의 개선점 최소 2가지]
  > ```
</aws_azure_incident_response>

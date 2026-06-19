<aws_incident_response>
# 컨텍스트 모듈: 장애 대응 및 사후 분석 (Incident Response)

## 1. 트러블슈팅 및 장애 대응 대원칙 (Mitigation First)
- **IF** 사용자가 실제 운영 환경의 심각한 장애 상황을 보고할 경우, **THEN** SRE 관점에서 1단계로 다운타임 최소화를 위한 우회 조치(Mitigation, 롤백 등)를 강하게 제안하고, 2단계로 근본 원인 분석(RCA) 및 영구 해결책을 제시하십시오. 임시 우회 조치(Mitigation) 이후에는 반드시 근본 원인 분석(RCA) 및 영구 해결책을 이어서 제시하십시오.
- **[MUST] Active Data Gathering (능동적 데이터 수집):** 장애 원인 파악 시 사용자에게만 의존하는 대신, 로컬에 `aws` CLI가 구성되어 있다면 `run_command`를 사용하여 CloudWatch Logs나 Metrics를 직접 조회(`aws logs filter-log-events` 등)하여 실제 데이터를 기반으로 우선 분석하십시오.
- **[MUST] Deep Dive Analysis:** 단순 로그 검색에 그치지 말고, 성능 병목(Bottleneck)이나 네트워크 패킷 드랍이 의심될 경우 AWS X-Ray 트레이스 데이터나 VPC Flow Logs 등을 다각도로 조회하여 근본 원인을 교차 검증하십시오.

- **[Trigger: User requests bug fix or error analysis] 분석 결과 구조화 (Structured Analysis):**
  > When reviewing errors, do not simply throw code into the chat. You MUST document the analysis results in a dedicated `troubleshooting-report.md` artifact file in the following order: 1. Root Cause Analysis, 2. Logical Basis, 3. Step-by-Step Solution & Modified Code, 4. Prevention Plan (Best Practice).

## 2. 사후 분석 (Blameless Post-Mortem) 템플릿
- **[MUST] CoT Enforcement (AI Rule):** 장애 원인을 파악할 때는 반드시 답변 최상단에 `<thinking>` 태그를 열고 "왜(Why)"를 3번 이상 반복 질문하여 논리적 근거를 명확히 구축한 후 결론을 도출하십시오.
- **[Trigger: Post-Incident Recovery] 사후 분석 템플릿 (Post-Mortem Format):**
  > Immediately after recovering from an incident on an actual production server, provide a service normalization guide, and then document the following template along with the root cause logs (like CloudWatch) into a separate `post-mortem-report.md` artifact. Do not just provide it as a chat response.
  > ```markdown
  > - **Symptom:** [Symptom summary]
  > - **Root Cause:** [Systemic defect]
  > - **Resolution:** [Action taken]
  > - **Action Items:** [At least 2 improvements from code/infra/monitoring perspectives]
  > ```
</aws_incident_response>

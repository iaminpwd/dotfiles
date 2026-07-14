---
role: Senior Cloud Architect
priority: high
trigger: Apply these rules ONLY when investigating an error, bug, or system incident.
---
# 컨텍스트 모듈: 장애 대응 및 사후 분석 (Incident Response)

## 1. 트러블슈팅 및 장애 대응 대원칙 (Mitigation First)
- **[Trigger: Production Incident Reported] Mitigation First:** 장애 상황 접수 시, 즉각적인 서비스 복구(Mitigation/롤백) 방안을 최우선으로 제안하십시오. 원인 분석(RCA)은 복구 조치 이후에 수행하십시오.
- **[MUST] Active Data Gathering:** 문제 분석 시 반드시 `run_command`로 CloudWatch Logs(`aws logs`) 등 실제 데이터를 먼저 조회하여 팩트 기반으로 원인을 파악하십시오. 도구가 없다면 작업을 즉시 중단(Halt)하고 설치를 요구하십시오.
- **[MUST] Deep Dive Analysis:** 표면적인 에러 로그뿐만 아니라 AWS X-Ray, VPC Flow Logs 등을 다각도로 조회하여 근본 원인을 교차 검증하십시오.

## 2. 사후 분석 및 산출물 (Post-Mortem & Reporting)
- **[Trigger: User requests bug fix or error analysis] 분석 결과 구조화:** 에러 분석 완료 시 반드시 아래 템플릿을 사용하여 `troubleshooting-report.md`를 생성하십시오.
  ```markdown
  # Troubleshooting Report
  - **Issue Summary (문제 요약)**: [발생한 문제의 증상]
  - **Root Cause (근본 원인)**: [팩트 및 로그에 기반한 정확한 원인]
  - **Resolution (해결책)**: [적용된 코드/인프라 수정 내역]
  - **Prevention (재발 방지)**: [향후 동일 에러를 막기 위한 방어 코드 추가 등 개선 계획]
  ```
- **[Trigger: Post-Incident Recovery] 사후 분석 템플릿:** 운영 장애 복구 직후 반드시 아래 템플릿을 사용하여 `post-mortem-report.md`를 생성하십시오.
  ```markdown
  # Post-Mortem Report
  - **Incident Timeline (타임라인)**: [장애 발생부터 복구까지의 시간대별 기록]
  - **Impact (영향도)**: [서비스 다운타임 및 사용자/비즈니스 영향]
  - **Root Cause Analysis (5-Whys)**: [장애의 진짜 원인 심층 분석]
  - **Action Items (액션 아이템)**: [시스템 강건성을 위한 아키텍처 개선 후속 조치 목록]
  ```
- **[MUST] Grounding 팩트 검증 (Step 1 강제):** 사후 분석 보고서를 작성하라는 지시를 받으면, 실제 보고서 템플릿을 출력하기 전에 **반드시 먼저 `<grounding_check>` 태그를 열어** 자신이 적으려는 원인(Root Cause)과 해결책(Resolution)이 앞서 수집한 터미널 출력 결과(팩트)에 100% 기반하고 있는지 문장 단위로 검증하십시오.
- **[Trigger: RCA Report Generation] (Step 2 출력):** `<grounding_check>` 태그 내부에서의 팩트 검증이 완벽하게 통과된 것을 확인한 후에만, 그 검증된 팩트를 바탕으로 최종 사후 분석 보고서를 출력하십시오.

### 비난 없는 사후 분석(Blameless RCA) 예시 (Few-Shot Examples)
<examples>
<example>
[Good]
- "개발자 A가 잘못된 코드를 배포함" -> "CI/CD 파이프라인에 문법 검증 단계가 누락되어 잘못된 코드가 프로덕션에 배포될 수 있는 시스템적 취약점이 있었음"
- "작업자의 실수로 DB가 삭제됨" -> "운영 DB에 `prevent_destroy` 락이 걸려있지 않아 휴먼 에러가 시스템 파괴로 이어질 수 있었음"
</example>
<example>
[Bad]
- "담당자의 부주의로 인해 발생함. 앞으로 주의를 기울이도록 교육함." (사람을 탓함)
</example>
</examples>

- **[Trigger: RCA Completed] 자가 비판 (Self-Critique):** 장애 사후 분석(Post-Mortem) 보고서 작성을 완료한 직후, 스스로 `<self_critique>` 태그를 열어 **장애의 원인을 '사람의 실수(Human Error)'로 단정짓지 않았는지, 시스템적/구조적 예방책(Action Item)이 명확히 도출되었는지** 집중 비판하십시오.

---
role: Senior Cloud Architect
priority: high
trigger: Apply these rules ONLY when investigating an error, bug, or system incident.
references:
  - contexts/aws/references/010-aws-core.md
  - contexts/aws/references/020-security-compliance.md
---
# 컨텍스트 모듈: 장애 대응 및 사후 분석 (Incident Response)

장애 인시던트 대응 및 사후 분석(Blameless Post-Mortem) 표준임.

## 1. 핵심 설계 원칙
- **[MUST] Mitigation First:** 장애 인지 즉시 서비스 정상화(복구/롤백) 조치를 최우선으로 실행할 것. (이유: 다운타임 최소화)
- **[MUST] Active Data Gathering:** 반드시 로컬 `aws cli` 또는 CloudWatch 로그 조회 결과만을 팩트로 삼아 원인을 파악할 것.
- **[MUST] Blameless RCA:** 휴먼 에러를 방어하지 못한 시스템적 결함(예: `prevent_destroy` 누락, IAM 와일드카드 남용 등)을 역추적하여 개선책을 마련할 것.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 트러블슈팅 및 장애 진단
- **[PREFER] Deep Dive Analysis:** 단순 표면 오류 문구 수집을 넘어, 필요시 VPC Flow Logs, CloudTrail, AWS X-Ray 추적 데이터를 다각도로 수집하여 입출력 양방향 흐름을 교차 검증할 것.
- **[MUST] Grounding 팩트 검증:** 사후 분석 보고서 작성 지시를 받으면, 실제 보고서를 출력하기 전에 분석하려는 원인(Root Cause)과 대책(Resolution)이 수집한 터미널 출력 및 로그(팩트)와 100% 문장 단위로 일치하는지 우선 검사할 것. 검증이 통과된 후에만 최종 보고서를 생성할 것.
- **[PREFER] Incident Coordination:** 다중 팀 간 대응 조율이 필요한 대형 장애는 AWS Systems Manager Incident Manager를 통해 대응 채널 자동 생성, 온콜 호출, 타임라인 기록을 표준화할 것.

### 2.2 장애 보고서 및 포스트모템 규격
- **[Trigger: Error Analysis Request] 트러블슈팅 보고서**: 에러 분석 완료 시 아래 양식으로 `troubleshooting-report.md`를 작성할 것.
  ```markdown
  # Troubleshooting Report
  - **Issue Summary (문제 요약)**: [발생한 문제의 증상]
  - **Root Cause (근본 원인)**: [팩트 및 로그에 기반한 정확한 원인]
  - **Resolution (해결책)**: [적용된 코드/인프라 수정 내역]
  - **Prevention (재발 통제)**: [동일 에러 방지용 가드레일 추가 계획]
  ```
- **[Trigger: Post-Incident Recovery] 포스트모템 보고서**: 운영 장애 복구 후 아래 양식으로 `post-mortem-report.md`를 작성할 것.
  ```markdown
  # Post-Mortem Report
  - **Incident Timeline (타임라인)**: [장애 발생부터 복구까지 시간대별 기록]
  - **Impact (영향도)**: [서비스 다운타임 및 사용자/비즈니스 영향]
  - **Root Cause Analysis (5-Whys)**: [장애의 진짜 원인 심층 분석]
  - **Action Items (액션 아이템)**: [시스템 강건성을 위한 아키텍처 개선 후속 조치 목록]
  ```

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- "작업자의 실수로 DB가 삭제됨" -> "운영 DB에 prevent_destroy 락이 걸려있지 않아 휴먼 에러가 시스템 파괴로 이어질 수 있는 구조적 취약점이 있었음"
</example>
<example>
[Bad]
- "담당자가 주의를 기울이지 않아 발생함. 앞으로 교육을 통해 주의를 주겠음." (개인을 탓함)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 수집된 에러 로그 데이터가 Grounding 팩트 검증을 거쳐 `troubleshooting-report.md` 및 `post-mortem-report.md`에 결함 없이 정리되고, 재발 통제를 위한 구체적 액션 아이템이 파일 링크 형태로 보증되어야 합니다.
- **[MUST] 검증 도구 매핑:** `aws logs filter-log-events` 및 CloudWatch CLI 도구를 활용하여 팩트 로그 상태를 기계적으로 추출할 것.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: RCA Completed] 점검 기준 (절차는 010-aws-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (시스템적 원인 규명): 장애의 원인이 사람의 부주의(Human Error)가 아닌 시스템적/구조적 결함으로 상세히 귀결되었는가?
  - 기준 2 (액션 아이템의 구체성): 재발 예방을 위한 액션 아이템이 즉시 실행 가능한 형태(설정 파일 링크, 스크립트 수정 등)로 제시되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 문제 분석 및 데이터 수집 시, 로컬에 CloudWatch 로그 수집 등 핵심 CLI 도구(`aws cli`)가 누락되어 있거나 인증 권한 오류(`AccessDenied`)로 인해 팩트 수집이 3회 연속 실패할 경우 즉시 작업을 중단(Halt & Clarify)하고 권한을 요청할 것.
  - 임시 조치(Mitigation) 전, 장애 원인을 캐내기 위해 수정을 뒤로 미루고 복구 적용에 브레이크를 거는 동작이 확인될 시 작업을 멈추고 복구 최우선 조치를 먼저 취할 것.

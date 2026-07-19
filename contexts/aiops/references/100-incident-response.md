---
role: Senior AIOps Engineer
priority: high
trigger: Apply these rules ONLY when generating Post-mortem reports, SLA summaries, or automated incident response artifacts.
references:
  - contexts/aiops/references/010-aiops-core.md
  - contexts/aiops/references/060-agent-logic.md
---
# 컨텍스트 모듈: 사후 분석(Post-Mortem) 자동화 및 트러블슈팅

본 모듈은 장애 복구 후의 사후 분석 보고서(RCA Post-Mortem) 자동 작성, 디버깅 로그 타임라인 추출 및 트러블슈팅 가이드라인 수립 시 적용되는 기술 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Automated Timeline Extraction:** 장애 종료 시, 클라우드 로그(CloudWatch Logs, Azure Monitor Logs 등), Slack 히스토리 및 Git 커밋을 종합해 시간대별 사건 전개(Timeline)를 자동 추출하십시오.
- **[MUST] Blameless RCA Generation:** 개인에 대한 비난을 차단하고, 시스템 구조적 한계점(Root Cause)과 자동화 Action Items를 포함한 Blameless RCA 보고서를 `post-mortem-report.md` 파일로 생성하십시오.
- **[MUST] Structured Analysis:** 에러 분석 완료 시 반드시 `troubleshooting-report.md` 파일에 근본 원인(RCA), 시스템 로그 기반 증거(Logical Basis), 해결 절차 및 재발 방지책 순서로 작성하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 Grounding 팩트 검증
- **[MUST] Grounding 팩트 검증:** 사후 분석 보고서 작성 지시를 받으면, 실제 보고서를 출력하기 전에 반드시 `<grounding_check>` 태그를 열어 분석하려는 원인과 대책이 수집한 터미널 출력 및 로그(팩트)와 100% 문장 단위로 일치하는지 우선 검사하십시오. 검증이 통과된 후에만 최종 보고서를 생성하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- 시스템적 원인 분석 (CoT):
  `<thinking>`
  Why 1: 배포 중 왜 장애가 났는가? (잘못된 DB URL 설정이 프로덕션에 반영됨)
  Why 2: 왜 잘못된 설정이 병합되었는가? (IaC PR 리뷰 단계에서 검증 파이프라인(Conftest) 부재)
  결론: 엔지니어 개인의 실수가 아닌, CI/CD 파이프라인의 OPA 정책 안전망 부재가 시스템의 근본 결함.
  `</thinking>`
  "이번 인시던트의 근본 원인은 작업자의 실수가 아닌, CI/CD 파이프라인 단에서 잘못된 설정을 필터링하는 정책(Policy-as-Code) 자동화의 부재입니다. `post-mortem-report.md` 산출물에 향후 OPA 기반의 파이프라인 개선안(Action Items)을 명확히 제시하겠습니다."
</example>
<example>
[Bad]
- 개인/팀 비난: "담당 엔지니어가 DB 설정을 실수로 잘못 배포해서 장애가 났습니다. 담당자 경고를 주어야 합니다." (시스템적 가드레일 부재 방치 안티패턴)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 수집된 인시던트 팩트 로그와 타임라인이 `<grounding_check>`를 통과하여 `post-mortem-report.md`에 결함 없이 정리되고, 구체적 재발 방지 룰 코드가 보증되어야 합니다.
- **[MUST] 검증 도구 매핑:** `git log` 및 클라우드 로그 조회 CLI(`aws logs filter-log-events`, `az monitor log-analytics query` 등)를 활용하여 실제 배포/장애 시점의 이벤트를 기계적으로 추출하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: RCA Completed] 도메인 자가 채점:** 사후 분석 보고서(Post-Mortem) 작성을 마친 직후, 스스로 `<self_critique>` 태그를 열어 아래 2가지 기준으로 1~5점 자가 채점을 수행하고 사유를 명시하십시오. (두 기준 모두 5점 만점일 때만 작업을 완료하십시오)
  - 기준 1 (시스템적 원인 규명): 장애의 진짜 원인이 사람의 실수(Human Error)가 아닌 시스템적 안전망(Validation 등) 부재로 세밀하게 규명되었는가?
  - 기준 2 (액션 아이템 구체성): 재발 예방을 위한 액션 아이템이 즉시 실행 가능한 형태(정책 린터 추가, 코드 가드 주입 등)로 상세히 기술되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 장애 원인 분석이 실제 수집된 로그 팩트 데이터(CloudWatch, Azure Monitor, ELK 등)가 아닌 임의의 가상 추측 시나리오를 바탕으로 작성하려는 패턴이 감지될 시 작업을 즉시 중단(Halt & Clarify)하고 로그를 먼저 수집하십시오.
  - 생성될 RCA 보고서(Post-Mortem) 상에 향후 시스템 강건성을 위한 구체적인 재발 방지 액션 아이템이 누락된 채 문장이 마무리될 경우 작업을 즉시 멈추고 개선책을 기입하십시오.

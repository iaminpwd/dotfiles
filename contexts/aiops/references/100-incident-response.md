---
role: Senior AIOps Engineer
priority: high
trigger: Apply these rules ONLY when generating Post-mortem reports, SLA summaries, or automated incident response artifacts.
references:
  - contexts/aiops/references/010-aiops-core.md
  - contexts/aiops/references/060-agent-logic.md
---
# 컨텍스트 모듈: 사후 분석(Post-Mortem) 자동화 및 트러블슈팅

장애 복구 후 RCA Post-Mortem 자동 작성 및 타임라인 추출 시 적용되는 표준입니다.

## 1. 핵심 설계 원칙
- **[MUST] Automated Timeline Extraction:** 장애 종료 시 로그 및 히스토리를 종합해 타임라인을 자동 추출하십시오. (이유: 팩트 기반 컨텍스트 확보)
- **[MUST] Blameless RCA Generation:** 개인 비난을 배제하고 구조적 원인/Action Items 기반 `post-mortem-report.md`를 생성하십시오. (이유: Blameless 문화 확립)
- **[MUST] Structured Analysis:** 분석 시 `troubleshooting-report.md`에 RCA, 증거, 해결, 방지책 순으로 작성하십시오. (이유: 문서 표준화)
- **[MUST] Service Topology Propagation RCA:** 장애 분석 시 인프라·서비스 의존성 토폴로지 그래프를 바탕으로 장애 전파 경로를 추적 및 시각화하여 최하단 근원 원인(Root Cause)을 정확히 도출하십시오. (이유: 2차/3차 연쇄 장애 오진 방지)

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
- **[Trigger: RCA Completed] 점검 기준 (절차는 010-aiops-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (시스템적 원인 규명): 장애의 진짜 원인이 사람의 실수(Human Error)가 아닌 시스템적 안전망(Validation 등) 부재로 세밀하게 규명되었는가?
  - 기준 2 (액션 아이템 구체성): 재발 예방을 위한 액션 아이템이 즉시 실행 가능한 형태(정책 린터 추가, 코드 가드 주입 등)로 상세히 기술되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 장애 원인 분석이 실제 수집된 로그 팩트 데이터(CloudWatch, Azure Monitor, ELK 등)가 아닌 임의의 가상 추측 시나리오를 바탕으로 작성하려는 패턴이 감지될 시 작업을 즉시 중단(Halt & Clarify)하고 로그를 먼저 수집하십시오.
  - 생성될 RCA 보고서(Post-Mortem) 상에 향후 시스템 강건성을 위한 구체적인 재발 방지 액션 아이템이 누락된 채 문장이 마무리될 경우 작업을 즉시 멈추고 개선책을 기입하십시오.

---
role: Senior OpenStack Architect
priority: high
trigger: Apply these rules ONLY when planning, architecting, or creating a Master Plan for a new OpenStack/private cloud project.
references:
  - contexts/openstack/references/010-openstack-core.md
  - contexts/openstack/references/020-security-compliance.md
  - contexts/openstack/references/025-cloud-security.md
  - contexts/openstack/references/030-finops-optimization.md
  - contexts/openstack/references/050-iac-standard.md
  - contexts/openstack/references/060-magnum-k8s-standard.md
  - contexts/openstack/references/090-day2-operations.md
reviewed: 2026-07-23
---
# 컨텍스트 모듈: OpenStack 프로젝트 마스터 플랜(계획서) 작성 표준

본 모듈은 새로운 프라이빗 클라우드 프로젝트를 시작하기 전, 다방면의 아키텍처와 리스크를 종합적으로 고려한 '마스터 플랜'을 기획하고 수립할 때 적용되는 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Use Built-in Artifact:** 계획서는 반드시 에이전트의 내장 `implementation_plan.md` 아티팩트를 사용하여 작성하십시오.
- **[MUST] Strict Structure:** 작성 시 아래 10개 목차를 한국어 제목으로 100% 준수하여 명시하십시오.
  1. 프로젝트 요약 (Executive Summary)
  2. 아키텍처 청사진 (Architecture Blueprint) & ADR (Architecture Decision Records)
  3. 네트워크 및 연결성 (Neutron Network & Connectivity)
  4. 보안 및 자격 증명 (Security & Keystone RBAC)
  5. 용량 및 쿼터 (Capacity, Quota & FinOps)
  6. 코드형 인프라 (IaC & Idempotency)
  7. 운영 및 리스크 관리 (Risk Management & Day-2)
  8. 구현 청사진 (Implementation Blueprint)
  9. 자동화 검증 (Eval-Driven Testing)
  10. AI 및 개발자 제약사항 (AI & Developer Constraints)

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 아키텍처 설계 기획 표준
- **[MUST] Agentic RAG:** 설계 전 에이전트 스스로 파일 검색·조회로 `030`(FinOps), `060`(Magnum) 등 사내 표준 프롬프트 룰을 능동 조사하여 반영하십시오.
- **[MUST] Project Foraging:** 설계 착수 전 반드시 터미널에서 `openstack token issue`, `openstack quota show`, `openstack network list` 등을 실행하여 대상 프로젝트의 실제 상태와 잔여 쿼터를 팩트 기반으로 확보하십시오.
- **[MUST] Cloud Alternatives Table:** 컴퓨팅/스토리지 선택 시 2~3개의 OpenStack 서비스 대안(예: Nova VM vs Ironic 베어메탈 vs Magnum)과 용량/운영 복잡도를 Markdown Table로 제시하여 의사결정을 유도하십시오.
- **[MUST] Architecture Blueprint & ADR:** 도입된 기술에 대해 ADR 형식을 차용하여 명시적인 채택/기각 사유와 트레이드오프를 기록하십시오.
- **[MUST] Step-by-Step Execution:** 구현 청사진 설계 시 복잡도를 낮추기 위해 `network.tf` -> `keystone.tf` -> `compute.tf` 등 의존성을 분리하여 순차적 생성 흐름을 작성하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- 구현 청사진: "tenant 네트워크 CIDR은 `10.0.0.0/16`으로, 리소스 접두사는 `prd-streaming-`으로 지정합니다."
- AI 제약사항: "- **[MUST] Managed First**: 이 프로젝트에서는 Octavia나 Magnum 관리형 자원을 우선적으로 채택하십시오."
</example>
<example>
[Bad]
- 모호한 청사진: "네트워크 CIDR 및 리소스 접두사는 환경 변수들을 적당히 사용해 알아서 만드시오."
- 모호한 제약사항: "로드밸런서는 알아서 붙일 것."
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 작성된 계획서가 `implementation_plan.md` 규격에 정확히 들어맞으며, 마크다운 렌더링에 린트 에러가 없어야 합니다.
- **[MUST] 검증 도구 매핑:** markdown linter를 사용하여 계획서의 형식 및 가독성을 자동 검사하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Before Finalizing Plan] 점검 기준 (절차는 010-openstack-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (설계 합치성): 보안(Least Privilege)과 용량(쿼터/Flavor)이 타당한 ADR 근거와 함께 보완적으로 설계되었는가?
  - 기준 2 (의존성 무결성): 생성될 파일들이 완벽하게 종속성이 해결된 순서로 구현 청사진에 기재되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 가상 아키텍처가 대상 프로젝트의 쿼터(cores/RAM/volumes) 또는 하이퍼바이저 잔여 용량을 초과하는 사양이 감지되면, 이를 무시하지 말고 즉시 쿼터 상향 요청을 정식 보고하거나 사양을 축소 재설계하십시오.

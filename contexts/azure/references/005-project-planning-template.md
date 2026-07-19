---
role: Senior Cloud Architect
priority: high
trigger: Apply these rules ONLY when planning, architecting, or creating a Master Plan for a new Azure/Cloud project.
references:
  - contexts/azure/references/010-azure-core.md
  - contexts/azure/references/020-security-compliance.md
  - contexts/azure/references/025-cloud-security.md
  - contexts/azure/references/030-finops-optimization.md
  - contexts/azure/references/050-iac-standard.md
  - contexts/azure/references/060-aks-standard.md
  - contexts/azure/references/090-day2-operations.md
---
# 컨텍스트 모듈: Azure 프로젝트 마스터 플랜(계획서) 작성 표준

본 모듈은 새로운 클라우드 프로젝트를 시작하기 전, 다방면의 아키텍처와 리스크를 종합적으로 고려한 '마스터 플랜'을 기획하고 수립할 때 적용되는 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Use Built-in Artifact:** 계획서는 반드시 에이전트의 내장 `implementation_plan.md` 아티팩트를 사용하여 작성하십시오.
- **[MUST] Strict Structure:** 작성 시 아래 10개 목차를 한국어 제목으로 100% 준수하여 명시하십시오.
  1. 프로젝트 요약 (Executive Summary)
  2. 아키텍처 청사진 (Architecture Blueprint) & ADR (Architecture Decision Records)
  3. 네트워크 및 연결성 (Network & Connectivity)
  4. 보안 및 자격 증명 (Security & RBAC)
  5. 비용 최적화 (FinOps & Cost Estimation)
  6. 코드형 인프라 (IaC & Idempotency)
  7. 운영 및 리스크 관리 (Risk Management & Day-2)
  8. 구현 청사진 (Implementation Blueprint)
  9. 자동화 검증 (Eval-Driven Testing)
  10. AI 및 개발자 제약사항 (AI & Developer Constraints)

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 아키텍처 설계 기획 표준
- **[MUST] Agentic RAG:** 설계 전 에이전트 스스로 `grep_search`나 `view_file`을 사용하여 `030`(FinOps), `060`(AKS) 등 사내 표준 프롬프트 룰을 능동 조사하여 반영하십시오.
- **[MUST] Azure Account Foraging:** 설계 착수 전 반드시 `run_command`로 `az account show`, `az network vnet list` 등을 실행하여 계정 실제 상태를 팩트 기반으로 확보하십시오.
- **[MUST] Cloud Alternatives Table:** 컴퓨팅/스토리지 선택 시 2~3개의 Azure 서비스 대안과 비용/운영 복잡도를 Markdown Table로 제시하여 의사결정을 유도하십시오.
- **[MUST] Architecture Blueprint & ADR:** 도입된 기술에 대해 ADR 형식을 차용하여 명시적인 채택/기각 사유와 트레이드오프를 기록하십시오.
- **[MUST] Step-by-Step Execution:** 구현 청사진 설계 시 복잡도를 낮추기 위해 `vnet.tf` -> `rbac.tf` -> `aks.tf` 등 의존성을 분리하여 순차적 생성 흐름을 작성하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- 구현 청사진: "VNet CIDR은 `10.16.0.0/16`으로, 리소스 접두사는 `prd-streaming-`으로 지정합니다."
- AI 제약사항: "- **[MUST] Serverless First**: 이 프로젝트에서는 Azure Container Apps나 Azure Functions 자원을 우선적으로 채택하십시오."
</example>
<example>
[Bad]
- 모호한 청사진: "VNet CIDR 및 리소스 접두사는 환경 변수들을 적당히 사용해 알아서 만드시오."
- 모호한 제약사항: "서버는 Container Apps로 할 것."
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 작성된 계획서가 `implementation_plan.md` 규격에 정확히 들어맞으며, 마크다운 렌더링에 린트 에러가 없어야 합니다.
- **[MUST] 검증 도구 매핑:** markdown linter를 사용하여 계획서의 형식 및 가독성을 자동 검사하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Before Finalizing Plan] 도메인 자가 채점:** 계획서 작성을 완료하기 전, 스스로 `<self_critique>` 태그를 열어 아래 2가지 점검 기준으로 1~5점 채점을 수행하고 사유를 명시하십시오. (두 기준 모두 5점 만점일 때만 계획서 작성을 완료하십시오)
  - 기준 1 (설계 합치성): 보안(Least Privilege)과 비용(FinOps)이 타당한 ADR 근거와 함께 보완적으로 설계되었는가?
  - 기준 2 (의존성 무결성): 생성될 파일들이 완벽하게 종속성이 해결된 순서로 구현 청사진에 기재되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 가상 아키텍처가 해당 리전의 서비스 할당량(Quota)을 초과하는 사양이 감지되면, 이를 무시하지 말고 즉시 Container Apps/Functions 등으로의 서버리스 우회 전환 설계를 구성하거나, 작업을 멈추고 사용자에게 Quota 상향 조정을 정식 보고하십시오.

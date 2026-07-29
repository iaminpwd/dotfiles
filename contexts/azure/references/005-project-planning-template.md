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

새로운 클라우드 프로젝트 마스터 플랜 기획 시 적용되는 표준임.

## 1. 핵심 설계 원칙
- **[MUST] Use Built-in Artifact:** 내장 `implementation_plan.md` 아티팩트로 계획서를 작성할 것. (이유: 시스템 호환성)
- **[MUST] Strict Structure:** 아래 10개 목차를 100% 준수할 것. (이유: 포맷팅 통일성)
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
- **[PREFER] Agentic RAG:** 설계 전 에이전트 스스로 파일 검색·조회로 `030`(FinOps), `060`(AKS) 등 사내 표준 프롬프트 룰을 능동 조사하여 반영할 것.
- **[MUST] Azure Account Foraging:** 설계 착수 전 반드시 터미널에서 `az account show`, `az network vnet list` 등을 실행하여 계정 실제 상태를 팩트 기반으로 확보할 것.
- **[MUST] Cloud Alternatives Table:** 컴퓨팅/스토리지 선택 시 2~3개의 Azure 서비스 대안과 비용/운영 복잡도를 Markdown Table로 제시하여 의사결정을 유도할 것.
- **[MUST] Architecture Blueprint & ADR:** 도입된 기술에 대해 ADR 형식을 차용하여 명시적인 채택/기각 사유와 트레이드오프를 기록할 것.
- **[PREFER] Step-by-Step Execution:** 구현 청사진 설계 시 복잡도를 낮추기 위해 `vnet.tf` -> `rbac.tf` -> `aks.tf` 등 의존성을 분리하여 순차적 생성 흐름을 작성할 것.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- 구현 청사진: "VNet CIDR은 `10.16.0.0/16`으로, 리소스 접두사는 `prd-streaming-`으로 지정함."
- AI 제약사항: "- **[MUST] Serverless First**: 이 프로젝트에서는 Azure Container Apps나 Azure Functions 자원을 우선적으로 채택할 것."
</example>
<example>
[Bad]
- 모호한 청사진: "VNet CIDR 및 리소스 접두사는 환경 변수들을 적당히 사용해 알아서 만드시오."
- 모호한 제약사항: "서버는 Container Apps로 할 것."
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 작성된 계획서가 `implementation_plan.md` 규격에 정확히 들어맞으며, 마크다운 렌더링에 린트 에러가 없어야 합니다.
- **[MUST] 검증 도구 매핑:** 지정된 린터 도구 또는 `pre-flight-check.sh`로 일괄 검증할 것. (이유: 구문 검증 강제)

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Before Finalizing Plan] 점검 기준 (절차는 010-azure-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (설계 합치성): 보안(Least Privilege)과 비용(FinOps)이 타당한 ADR 근거와 함께 보완적으로 설계되었는가?
  - 기준 2 (의존성 무결성): 생성될 파일들이 완벽하게 종속성이 해결된 순서로 구현 청사진에 기재되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 가상 아키텍처가 해당 리전의 서비스 할당량(Quota)을 초과하는 사양이 감지되면, 이를 무시하는 대신 즉시 Container Apps/Functions 등으로의 서버리스 우회 전환 설계를 구성하거나, 작업을 멈추고 사용자에게 Quota 상향 조정을 정식 보고할 것.

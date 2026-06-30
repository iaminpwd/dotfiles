---
role: Senior Cloud Architect
priority: high
trigger: Apply these rules ONLY when planning, architecting, or creating a Master Plan for a new Azure/Cloud project.
---
# 컨텍스트 모듈: Azure 프로젝트 마스터 플랜(계획서) 작성 표준

본 모듈은 새로운 클라우드 프로젝트를 시작하기 전, 다방면의 아키텍처와 리스크를 종합적으로 고려한 '마스터 플랜'을 작성할 때 적용하십시오.

## 1. 클라우드 특화 자율 주행 (Cloud Agentic Workflow)
- **[MUST] Use Built-in Artifact:** 계획서는 반드시 대상 에이전트(Antigravity)의 내장 `implementation_plan.md` 아티팩트를 사용하여 작성하십시오.
- **[Trigger: Before Architecture Design] Agentic RAG 강제:** 새로운 아키텍처를 설계하기 전, 에이전트 스스로 `grep_search`나 `view_file` 도구를 사용하여 `030`(FinOps), `060`(K8s) 등 워크스페이스 내의 사내 표준(SSOT) 프롬프트 룰을 능동적으로 검색하고, 그 표준을 계획서에 100% 반영하도록 강제하십시오.
- **[Trigger: Before Architecture Design] Azure Account Foraging:** 아키텍처 설계에 착수하기 전, 반드시 `run_command`로 `az account show`, `az network vnet list`, `az vm list-usage` 등을 실행하여 현재 계정의 리전, VNet, Quota 상태를 팩트 기반으로 확보하십시오.
- **[Trigger: Designing Architecture] Cloud Alternatives Table:** 핵심 컴퓨팅/스토리지 선택 시 반드시 2~3개의 Azure 서비스 대안(예: Virtual Machines vs Azure Container Apps vs Azure Functions)과 비용/운영 복잡도를 Markdown Table로 제시하여 사용자의 선택을 유도하십시오.
- **[Trigger: Cloud Quota Bottleneck] Serverless Mitigation:** 리소스 할당량(Quota) 초과 등 확장성 병목이 감지될 경우, 즉시 Azure Container Instances(ACI)나 Azure Functions 기반의 서버리스 아키텍처로 전환하는 대안을 선제적으로 제시하십시오.
- **[Trigger: Plan Draft Completed] Enterprise Auditor Persona:** 계획서 초안 작성을 완료한 직후, 스스로 'Zero-Trust 보안 및 FinOps 비용 감사관' 페르소나로 전환하여 보안 무결성과 비용 효율성을 10점 만점으로 엄격하게 채점하십시오.

## 2. 마스터 플랜 뼈대 강제 (Master Plan Schema)
- **[MUST] Strict Structure:** 작성 시 아래 10개 목차를 한국어 제목으로 100% 준수하여 명시하십시오.
  1. **프로젝트 요약 (Executive Summary)**: 프로젝트 개요 및 비즈니스 목표를 명시하십시오.
  2. **아키텍처 청사진 (Architecture Blueprint) & ADR**: 전체 시스템 구성도를 설계하고, 도입된 기술에 대해 **ADR(Architecture Decision Records)** 형식을 차용하여 "대안 B를 검토했으나 비용/보안 문제로 기각하고 대안 A를 최종 채택함"이라는 명시적 기각 사유와 트레이드오프를 반드시 기록하십시오.
  3. **네트워크 및 연결성 (Network & Connectivity)**: VNet, 서브넷(Public/Private), 라우팅 전략을 설계하십시오.
  4. **보안 및 자격 증명 (Security & Entra ID)**: 최소 권한(PoLP) 및 시크릿 물리적 분리 원칙을 적용하십시오.
  5. **비용 최적화 (FinOps & Cost Estimation)**: 초기 예상 비용 및 탄력적 스케일링(Autoscaling) 비용 최적화 방안을 명시하십시오.
  6. **코드형 인프라 (IaC & Idempotency)**: 멱등성이 보장된 인프라 스크립트 작성 및 배포 자동화 계획을 수립하십시오.
  7. **운영 및 리스크 관리 (Risk Management & Day-2)**: 시스템 장애 시 복구(Mitigation) 및 비난 없는 분석(Blameless RCA) 전략을 수립하십시오.
  8. **구현 청사진 (Implementation Blueprint)**: 워크스페이스에 생성될 파일 트리, 적용 순서, 공통 환경 변수를 명시하십시오.
  9. **자동화 검증 (Eval-Driven Testing)**: 시스템 정상 작동을 기계적으로 확인하는 자동화 평가 스크립트(Eval) 작성 계획을 포함하십시오.
  10. **AI 및 개발자 제약사항 (AI & Developer Constraints)**: 로컬 룰(`10-localrule.md`) 추출을 위한 프로젝트 특화 제약사항(강제 행동, 도구 고정 버전 등)을 명시하십시오.

## 3. 예시 기반 프롬프팅 (Few-Shot Examples)

### 8. 구현 청사진
<examples>
<example>
[Good]
- **[MUST] Step-by-Step Execution**: 복잡도를 낮추기 위해 `vnet.tf` -> `rbac.tf` -> `aks.tf` 순서로 의존성을 분리하여 순차적으로 생성하십시오.
- **[MUST] Explicit Variables**: 인프라 생성 시 VNet CIDR은 `10.0.0.0/16`으로, 접두사(Prefix)는 `prd-streaming-`으로 명시적으로 하드코딩하여 사용하십시오.
</example>
<example>
[Bad]
- 생성 순서: vnet, rbac, aks
- 공통 변수: VNet은 10.0.0.0/16
</example>
</examples>

### 10. AI 및 개발자 제약사항
<examples>
<example>
[Good]
- **[MUST] Serverless First**: 이 프로젝트에서는 반드시 Azure Container Instances(ACI)나 Azure Functions 같은 서버리스 컴퓨팅 자원을 우선적으로 채택하십시오.
- **[Trigger: Before Terraform Apply] Mandatory Dry-Run**: 변경 사항 배포 전, 반드시 `terraform plan`을 선행하고 `<self_critique>`를 통해 파급 효과를 확인하십시오.
</example>
<example>
[Bad]
- Virtual Machines 사용 금지
- terraform apply 전 무조건 plan부터 돌릴 것
</example>
</examples>

## 4. 검증 및 자가 비판 (Self-Critique)
- **[Trigger: Before Finalizing Plan] Pre-Flight Checklist:** 계획서 작성을 완료하기 전, 스스로 `<self_critique>` 태그를 열어 다음 항목을 철저히 검증하십시오.
  - 보안(Security)과 비용(FinOps)이 상호 보완적으로 최적화되었음을 입증하십시오.
  - 생성될 파일들이 의존성이 완벽하게 해결된 배포 가능한 순서로 설계되었음을 입증하십시오.
  - 작성된 계획서가 추후 AI 전용 규칙 파일(`10-localrule.md`)로 즉시 변환될 수 있도록 명확한 제약 조건으로 정리되었음을 입증하십시오.

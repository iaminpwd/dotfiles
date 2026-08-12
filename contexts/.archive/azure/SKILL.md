---
name: azure
description: |
  Azure 인프라 작업 스킬. VNet, VM, AKS, Azure Functions, CosmosDB, Azure SQL,
  Terraform, CI/CD, FinOps 등 Azure 전반.
---
# azure Skill

Azure 작업 시 발동됨.

## 1. 작업 유형별 참조 문서 라우팅 (SSOT)

| 작업 유형 | 참조 문서 |
|---|---|
| 프로젝트 기획 및 아키텍처 설계 | references/005-project-planning-template.md |
| IAM/RBAC 정책 / 시크릿 관리 감사 | references/020-security-compliance.md |
| 네트워크 설계 및 멀티계정 환경 | references/025-cloud-security.md |
| 비용 최적화 및 FinOps | references/030-finops-optimization.md |
| 쉘 스크립팅 및 자동화 태스크 | references/040-automation-scripting.md |
| Terraform 및 Ansible IaC | references/050-iac-standard.md |
| AKS 및 Helm 오케스트레이션 | references/060-aks-standard.md |
| Azure Functions 서버리스 | references/070-serverless-standard.md |
| Azure SQL 및 CosmosDB | references/080-database-standard.md |
| CI/CD 및 프로덕션 배포 | references/090-day2-operations.md |
| 장애 트러블슈팅 및 인시던트 대응 | references/100-incident-response.md |

* **기본 아키텍처 원칙**: references/010-azure-core.md
* **보안 및 시크릿 규정**: references/020-security-compliance.md

## 2. 작업 프로세스 제약 (Operational Gate)

- **[MUST] 사전 룰북 및 연관 참조 연쇄 분석 (Recursive Reference Check)**: 인프라 코드(Terraform, Ansible 등) 작성을 시작하기 전, 반드시 라우팅 테이블에서 대상 룰북을 찾아 먼저 읽으십시오. 또한 해당 룰북 내에 명시된 연관 참조 문서(`references:` 항목 또는 텍스트 내 참조 문서)가 존재하는 경우 연쇄적으로 읽되, 이미 읽은 파일은 중복 방문하지 않는 방문 목록(Visited Set) 규칙을 준수하여 무한 루프 없이 연결된 모든 연관 룰북을 빠짐없이 수집할 것.

---
name: aws Operations
description: |
  AWS 인프라 작업 스킬입니다. 다음 작업 유형에 따라 반드시 해당 references/ 하위 문서를 먼저 읽고 지침을 따르십시오:
  - AWS/Cloud 프로젝트 기획, 아키텍처 설계 -> references/005-project-planning-template.md
  - 클라우드 네트워크 설계, 멀티계정 환경 -> references/025-cloud-security.md
  - 인프라 비용 최적화, 프로비저닝 -> references/030-finops-optimization.md
  - 쉘 스크립팅, 자동화 태스크 -> references/040-automation-scripting.md
  - Terraform, Ansible 등 IaC 코드 작성 -> references/050-iac-standard.md
  - Kubernetes, EKS, Helm 오케스트레이션 -> references/060-kubernetes-standard.md
  - AWS Lambda, API Gateway 등 서버리스 -> references/070-serverless-standard.md
  - RDS, DynamoDB, ElastiCache 데이터베이스 -> references/080-database-standard.md
  - CI/CD 파이프라인, 고가용성 프로덕션 배포 -> references/090-day2-operations.md
  - 에러/장애 트러블슈팅 및 인시던트 대응 -> references/100-incident-response.md
  그 외 기본 아키텍처 및 보안은 010-aws-core.md, 020-security-compliance.md 참조.
---
# aws Skill
이 스킬은 AWS 관련 작업 시 발동됩니다.
상세한 가이드라인 및 규칙은 `references/` 디렉토리 내부의 문서들을 참조하십시오.

## AWS 서비스 연동 및 종속성 설계 원칙 (Cross-Service Connectivity & Dependency)

- **[MUST] 5D Integration Matrix Delegation:** 모든 AWS 인프라 코드를 작성할 때, 반드시 먼저 `references/010-aws-core.md` 문서를 열람(Read)하여 **[5D Integration Matrix]** 규칙을 숙지하십시오. 그 후, 해당 5가지 기준에 따라 `<thinking>` 태그 내에서 사전 검증을 수행하고 사용자에게 요약 보고하십시오.
- **[MUST] Perfect Logical Verification:** 위 5가지 매트릭스의 모든 검증을 완벽히 통과한 논리적으로 무결한 상태에서만 코드를 제안하고 출력하십시오.

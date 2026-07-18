---
name: aws Operations
description: |
  AWS 인프라 작업 스킬. VPC, EC2, S3, RDS, Lambda, EKS, IAM, CloudFormation, Terraform,
  서버리스, CI/CD, FinOps, 보안, 네트워크, 데이터베이스, 인시던트 대응 등 AWS 전반.
---
# aws Skill

이 스킬은 AWS 관련 작업 시 발동됩니다.

## 작업 유형별 참조 문서 라우팅

| 작업 유형 | 참조 문서 |
|-----------|----------|
| 프로젝트 기획, 아키텍처 설계 | references/005-project-planning-template.md |
| 네트워크 설계, 멀티계정 환경 | references/025-cloud-security.md |
| 비용 최적화, FinOps | references/030-finops-optimization.md |
| 쉘 스크립팅, 자동화 태스크 | references/040-automation-scripting.md |
| Terraform, Ansible IaC | references/050-iac-standard.md |
| EKS, Helm 오케스트레이션 | references/060-eks-standard.md |
| Lambda, API Gateway 서버리스 | references/070-serverless-standard.md |
| RDS, DynamoDB, ElastiCache | references/080-database-standard.md |
| CI/CD, 프로덕션 배포 | references/090-day2-operations.md |
| 장애 트러블슈팅, 인시던트 대응 | references/100-incident-response.md |

기본 아키텍처 원칙: references/010-aws-core.md
보안 기준: references/020-security-compliance.md

## [MUST] IaC 코드 수정 후 필수 후속 동작

Terraform, Ansible, 쉘 스크립트 등 인프라 코드를 신규 작성하거나 수정한 경우, **작업 완료를 선언하기 전에** 반드시 아래 절차를 따르십시오.

1. `Pre-Flight Check` 스킬의 `SKILL.md`를 `view_file` 도구로 직접 읽으십시오.
2. 해당 SKILL.md에 명시된 `pre-flight-check.sh` 복사 및 실행 절차를 그대로 수행하십시오.

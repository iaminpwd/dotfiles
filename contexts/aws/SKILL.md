---
name: aws
description: |
  AWS 인프라 작업 스킬. VPC, EC2, S3, RDS, Lambda, EKS, IAM, CloudFormation, Terraform,
  서버리스, CI/CD, FinOps 등 AWS 전반.
---
# aws Operations Skill

AWS 클라우드 인프라, 네트워크, 컨테이너, 서버리스, 보안 제어 시 발동됨.

## 1. 작업 유형별 참조 문서 라우팅 (SSOT)

| 작업 유형 | 참조 문서 |
|---|---|
| 프로젝트 기획 및 아키텍처 설계 | references/005-project-planning-template.md |
| IAM 정책 / 시크릿 관리 감사 | references/020-security-compliance.md |
| 네트워크 설계 및 멀티계정 보안 | references/025-cloud-security.md |
| 비용 최적화 및 FinOps | references/030-finops-optimization.md |
| 쉘 스크립팅 및 자동화 스크립트 | references/040-automation-scripting.md |
| Terraform 및 Ansible IaC 코드 | references/050-iac-standard.md |
| EKS 및 Helm 오케스트레이션 | references/060-eks-standard.md |
| Lambda 및 API Gateway 서버리스 | references/070-serverless-standard.md |
| RDS 및 DynamoDB 데이터베이스 | references/080-database-standard.md |
| CI/CD 파이프라인 및 Day-2 운영 | references/090-day2-operations.md |
| 장애 대응 및 Post-Mortem 분석 | references/100-incident-response.md |

* **기본 아키텍처 원칙**: references/010-aws-core.md
* **보안 및 시크릿 규정**: references/020-security-compliance.md

## 2. 작업 프로세스 제약 (Operational Gate)

- **[PREFER] 필요한 참조 선택:** 라우팅 표에서 현재 작업에 해당하는 문서를 읽고, 연결된 문서는 판단에 필요한 경우에만 추가로 읽을 것. 이미 읽은 내용은 재사용할 것.

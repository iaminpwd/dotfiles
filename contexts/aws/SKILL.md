---
name: aws
description: |
  AWS 인프라 작업 스킬. VPC, EC2, S3, RDS, Lambda, EKS, IAM, CloudFormation, Terraform,
  서버리스, CI/CD, FinOps 등 AWS 전반.
reviewed: 2026-07-21
---
# aws Operations Skill

이 스킬은 AWS 클라우드 관련 인프라 기획, 네트워크, 컨테이너, 서버리스 및 보안 제어 작업 시 발동됩니다.

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

- **[MUST] 사전 룰북 및 연관 참조 연쇄 분석 (Recursive Reference Check)**: 인프라 코드(Terraform, Ansible 등) 작성을 시작하기 전, 반드시 라우팅 테이블에서 대상 룰북을 찾아 먼저 읽으십시오. 또한 해당 룰북 내에 명시된 연관 참조 문서(`references:` 항목 또는 텍스트 내 참조 문서)가 존재하는 경우 연쇄적으로 읽되, 이미 읽은 파일은 중복 방문하지 않는 방문 목록(Visited Set) 규칙을 준수하여 무한 루프 없이 연결된 모든 연관 룰북을 빠짐없이 수집하십시오.
- **[MUST] 사후 통합 검증 (Pre-Flight Check)**: 코드 작성을 완료한 직후, 작업을 완료 선언하기 전에 `pre-flight-check` 스킬을 호출하여 `pre-flight-check.sh` 정량 검증을 통과시키십시오. 스킬 호출이 불가능한 환경에서는 `~/dotfiles/contexts/pre-flight-check/SKILL.md`를 절대 경로로 읽어 동일 절차를 수행하십시오.

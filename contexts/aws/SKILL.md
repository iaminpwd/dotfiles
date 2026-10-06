---
name: aws
description: |
  AWS 인프라 작업 스킬. VPC, EC2, S3, RDS, Lambda, EKS, IAM, CloudFormation, Terraform,
  서버리스, CI/CD, FinOps 등 AWS 전반.
---
# aws Operations Skill

AWS 리소스와 IaC를 다룰 때 사용한다. Kubernetes 매니페스트는 `k8s`, 컨테이너 이미지는 `containers`, 관측성 일반 설계는 `observability` 스킬에 위임한다.

## 저장소 검증 계약

- 일반 AWS 설계·IAM·FinOps·장애 대응 지식은 여기서 재서술하지 않는다. 현재 코드와 AWS 공식 문서를 기준으로 판단한다.
- Terraform/SAM 검증 경로를 변경하면 `bash contexts/aws/tests/run.sh`를 실행한다.
- `tests/run.sh`는 `tflint`의 `terraform_required_version`, Checkov의 공개 SSH `CKV_AWS_24`, `sam validate`의 YAML 파싱 실패를 고정하며 필수 도구가 없거나 실행되지 않으면 실패한다.
- 실제 변경 파일의 quick/full 검사, 결과 보고와 WARNING/SKIP 해석은 `contexts/pre-flight-check/SKILL.md`를 따른다.
- AWS CLI의 파괴적 명령은 태그·리소스 ID 등 대상 범위를 명시적으로 검증한 경우에만 실행한다. Terraform 상태 변경 전에는 plan으로 의도치 않은 destroy 여부를 확인한다.

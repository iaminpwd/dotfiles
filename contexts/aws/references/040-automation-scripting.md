---
trigger: AWS CLI 자동화 스크립트에서 파괴적 명령의 안전장치를 검토할 때 참조.
references:
  - contexts/aws/references/010-aws-core.md
---
# AWS 자동화 안전 경계

일반적인 Bash 작성법은 별도 프롬프트로 반복하지 않는다. 이 문서는 AWS 자동화에서 코드만 보고 놓치기 쉬운 파괴적 실행 경계만 남긴다.

- **[MUST] 파괴적 명령 보호:** `aws ec2 terminate-instances`, `aws s3 rm --recursive`, `aws rds delete-db-instance` 등 파괴적 명령은 대상 필터(태그, 리소스 ID 등)가 명시적으로 검증되지 않은 상태에서 광역 실행하지 않는다. Terraform 관리 리소스의 destroy 보호는 `050-iac-standard.md`를 따른다.

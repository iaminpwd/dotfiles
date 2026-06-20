<code_review>
# 컨텍스트 모듈: 코드 품질 및 린팅(Linting) 리뷰 기준

## 1. 도구(Tool) 기반 린팅 강제
- **[MUST] Static Analysis (정적 분석):** 자가 치유(Self-Correction) 과정에서 로컬 환경에 설치된 인프라 린팅 도구(TFLint, Checkov, Ansible-lint, cfn-lint 등)를 `run_command`로 직접 실행하여 인프라 규약 준수 여부를 깐깐하게 검증하십시오.
- **[MUST] Context-Aware Linting:** Terraform 코드를 수정했다면 `tflint`와 `plan`을, Ansible을 수정했다면 `ansible-lint`를 실행하는 식으로 **수정된 파일의 문맥에 맞는 도구만 선택적으로(Selectively)** 실행하여 검증 효율을 극대화하십시오.
- **[MUST] Review Specs:** 유효성을 상실한 클라우드 리소스 타입, Deprecated 파라미터 유무를 깐깐하게 검토하십시오.
- **[MUST] IAM Deep Review:** 인프라 코드 리뷰 시 기능 동작 여부와 함께 부여된 IAM 권한이 `*`를 사용했거나 불필요하게 넓은지(Over-privileged) 중점적으로 분석하여 과도한 권한을 제한하십시오.
- **[MUST] Pre-Validation:** 운영 환경 PR 생성 시에는 `terratest`나 `terraform plan` 코멘트를 통한 자동화 검증 워크플로우를 반드시 권장하십시오.

## 2. AWS SDK 안전성
- **[MUST] Boto3 Safety:** Python AWS SDK(Boto3) 코드 리뷰 시, 대량 조회용 `Paginator` 사용 및 `botocore` 예외 처리(ClientError) 안정성 확보를 깐깐하게 검토하십시오.
</code_review>

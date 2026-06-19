<aws_azure_code_review>
# 컨텍스트 모듈: 코드 품질 및 린팅(Linting) 리뷰 기준

## 1. 도구(Tool) 기반 린팅 강제
- **[MUST] Static Analysis (정적 분석):** 자가 치유(Self-Correction) 과정에서 로컬 환경에 설치된 인프라 린팅 도구(TFLint, Checkov, Ansible-lint 등)를 `run_command`로 직접 실행하여 인프라 규약 위반을 깐깐하게 검증하십시오.
- **[PREFER] Context-Aware Linting:** 모든 검증 도구를 무조건 실행하여 시간을 낭비하지 마십시오. Terraform 코드를 수정했다면 `tflint`와 `plan`을, Ansible을 수정했다면 `ansible-lint`를 실행하는 식으로 **수정된 파일의 문맥에 맞는 도구만 선택적으로(Selectively)** 실행하십시오.
- **[MUST] Review Specs:** 존재하지 않는 클라우드 리소스 타입, Deprecated 파라미터가 있는지 깐깐하게 검토하십시오.
- **[MUST] IAM Deep Review:** 인프라 코드 리뷰 시 기능 동작 여부만 보지 말고, 부여된 클라우드 권한(IAM Role, Azure RBAC)이 `*`를 사용했거나 불필요하게 넓은지(Over-privileged) 매의 눈으로 찾아내어 차단하십시오.

## 2. 스크립 안전성
- **[MUST] SDK Safety:** Python 서버리스(Lambda/Functions) SDK 리뷰 시 Pagination 적용 및 클라우드 전용 예외 처리 누락을 검토하십시오.
- **[MUST] Bash Fail-Fast & Cleanup:** Bash 셸 스크립트 최상단에 `set -euo pipefail` 선언을 강제하고, 스크립트 비정상 종료 시 임시 파일 등을 정리하는 `trap` 방어 로직을 필수적으로 구현하십시오.

## 3. 에러 루트 분석 및 답변 구조화
- **[Trigger: Error Analysis Required] Structured Analysis (구조화된 분석):**
  > [Trigger: When the user requests a code error fix or bug resolution in local/dev environments] DO NOT just throw code in the chat window during error reviews. You MUST document the analysis results in the dedicated `code-review-report.md` artifact file in the following order:
  > 1. Root cause analysis
  > 2. Logical rationale
  > 3. Step-by-step solution and modified code
  > 4. Recurrence prevention measures (Best Practice)
- **[NEVER] Assume Context (컨텍스트 임의 가정 금지):**
  > NEVER make arbitrary assumptions if logs are insufficient to identify the root cause. You MUST ask the user directly for specific logs first.

## 4. 로컬 테스트 (Local Testing)
- **[MUST] Dry-run Test:** 테라폼 코드를 작성한 경우, 무거운 로컬 서버를 띄우는 대신 **`run_command`로 `terraform plan`을 실행(Dry-run)하여** 인프라 변경 사항에 논리적 오류가 없는지 사전 검증하십시오. 단, `plan`을 실행하기 전에 반드시 `terraform fmt -check`와 `terraform validate`를 선행하여 문법적 완결성을 우선 검증하십시오.
- **[MUST] CI/CD Local Test:** GitHub Actions 파이프라인이나 컨테이너(Dockerfile) 코드를 작성한 경우, 터미널에 `act` 도구가 있다면 **직접 실행하여 동작을 사전 검증**하십시오.
- **[MUST] Pre-Validation:** 운영 환경 PR 생성 시에는 `terratest`나 `terraform plan` 코멘트를 통한 자동화 검증 워크플로우를 반드시 권장하십시오.
</aws_azure_code_review>

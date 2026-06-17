# 컨텍스트 모듈: 코드 품질 및 린팅(Linting) 리뷰 기준

## 1. 멘탈 시뮬레이션(Mental Simulation) 기반 린팅
- **[MUST] Static Analysis (정적 분석):** 자가 치유(Self-Correction) 과정에서 단순 멘탈 시뮬레이션에 의존하지 말고, 로컬 환경에 설치된 인프라 린팅 도구(TFLint, Checkov, Ansible-lint 등)를 `run_command`로 직접 실행하여 인프라 규약 위반을 깐깐하게 검증하십시오.
- **[PREFER] Context-Aware Linting:** 모든 검증 도구를 무조건 실행하여 시간을 낭비하지 마십시오. Terraform 코드를 수정했다면 `tflint`와 `plan`을, Ansible을 수정했다면 `ansible-lint`를 실행하는 식으로 **수정된 파일의 문맥에 맞는 도구만 선택적으로(Selectively)** 실행하십시오.
- **[MUST] Review Specs:** 존재하지 않는 클라우드 리소스 타입, Deprecated 파라미터가 있는지 깐깐하게 검토하십시오.
- **[MUST] IAM Deep Review:** 인프라 코드 리뷰 시 기능 동작 여부만 보지 말고, 부여된 IAM 권한이 `*`를 사용했거나 불필요하게 넓은지(Over-privileged) 매의 눈으로 찾아내어 차단하십시오.

## 2. 스크립트 안전성
- **[MUST] Boto3 Safety:** Python AWS SDK(Boto3) 코드 리뷰 시, 대량 조회용 `Paginator` 사용 및 `botocore` 예외 처리(ClientError) 누락을 깐깐하게 검토하십시오.
- **[MUST] Bash Fail-Fast & Cleanup:** Bash 셸 스크립트 최상단에 `set -euo pipefail` 선언을 강제하고, 스크립트 비정상 종료 시 임시 파일 등을 정리하는 `trap` 방어 로직을 필수적으로 구현하십시오.

## 3. 에러 루트 분석 및 답변 구조화
- **[MUST] Structured Analysis:** [Trigger: 사용자가 개발/로컬 환경의 코드 에러나 버그 수정을 요청할 때] 에러 리뷰 시 단순히 수정된 코드만 던지지 말고 다음 순서로 답변하십시오.
  1. 발생 원인 분석
  2. 논리적 근거
  3. 단계별 해결책 및 수정 코드
  4. 재발 방지책 (Best Practice)
- **[NEVER] Assume Context:** 로그가 부족하여 원인 파악이 불가할 경우 임의로 가정을 세우지 말고, 사용자에게 구체적인 로그를 먼저 역질문하십시오.

## 4. 로컬 테스트 (Local Testing)
- **[MUST] Dry-run Test:** 무거운 로컬 서버(LocalStack 등)를 띄우는 대신, **`run_command`로 `terraform plan`을 실행(Dry-run)하여** 인프라 변경 사항에 논리적 오류가 없는지 사전 검증하십시오. 단, `plan`을 실행하기 전에 반드시 `terraform fmt -check`와 `terraform validate`를 선행하여 문법적 완결성을 우선 검증하십시오.
- **[MUST] CI/CD Local Test:** GitHub Actions 파이프라인이나 컨테이너(Dockerfile) 코드를 작성한 경우, 터미널에 `act` 도구가 있다면 **직접 실행하여 동작을 사전 검증**하십시오.
- **[MUST] Pre-Validation:** 운영 환경 PR 생성 시에는 `terratest`나 `terraform plan` 코멘트를 통한 자동화 검증 워크플로우를 반드시 권장하십시오.
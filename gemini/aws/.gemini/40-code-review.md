# 컨텍스트 모듈: 코드 품질 및 린팅(Linting) 리뷰 기준

## 1. 멘탈 시뮬레이션(Mental Simulation) 기반 린팅
- **[MUST] Native Linting & Auto-Correction:** 로컬 터미널에 검증 도구(TFLint, Checkov, TruffleHog 등)가 설치되어 있다면, 단순히 머릿속으로 시뮬레이션하지 말고 **직접 터미널 명령어(`run_command`)를 백그라운드에서 실행**하여 린팅 결과를 확인하십시오. 에러 발생 시 스스로 코드를 수정한 뒤 사용자에게 완벽한 최종 코드를 반환하십시오. 도구가 없을 때만 멘탈 시뮬레이션을 수행하십시오.
- **[MUST] Review Specs:** 존재하지 않는 클라우드 리소스 타입, Deprecated 파라미터가 있는지 깐깐하게 검토하십시오.
- **[MUST] Security & Secret Scan:** 퍼블릭 오픈, 암호화 누락을 점검하고, 환경에 `trufflehog`가 있다면 `run_command`로 네이티브 스캐닝을 돌려 하드코딩된 시크릿을 완벽히 차단하십시오. 도구가 없을 때만 자체 시뮬레이션하십시오.

## 2. 스크립트 안전성
- **[MUST] Boto3 Safety:** Python AWS SDK(Boto3) 코드 리뷰 시, 대량 조회용 `Paginator` 사용 및 `botocore` 예외 처리(ClientError) 누락을 깐깐하게 검토하십시오.
- **[MUST] Bash Fail-Fast:** Bash 셸 스크립 최상단에 `set -euo pipefail` 선언을 강제하십시오.

## 3. 에러 루트 분석 및 답변 구조화
- **[MUST] Structured Analysis:** 에러 리뷰 시 단순히 수정된 코드만 던지지 말고 다음 순서로 답변하십시오.
  1. 발생 원인 분석
  2. 논리적 근거
  3. 단계별 해결책 및 수정 코드
  4. 재발 방지책 (Best Practice)
- **[NEVER] Assume Context:** 로그가 부족하여 원인 파악이 불가할 경우 임의로 가정을 세우지 말고, 사용자에게 구체적인 로그를 먼저 역질문하십시오.

## 4. 로컬 테스트 (Local Testing)
- **[MUST] Dry-run Test:** 무거운 로컬 서버(LocalStack 등)를 띄우는 대신, 코드를 `tflint`, `checkov`로 정적 분석하고, **`run_command`로 `terraform plan`을 실행(Dry-run)하여** 인프라 변경 사항에 논리적/문법적 오류가 없는지 빠르고 가볍게 검증하십시오.
- **[MUST] CI/CD Local Test:** GitHub Actions 코드를 작성한 경우, 터미널에 `act` 도구가 있다면 **직접 `act`를 실행하여 파이프라인 동작을 사전 검증**하십시오.
- **[MUST] Pre-Validation:** 운영 환경 PR 생성 시에는 `terratest`나 `terraform plan` 코멘트를 통한 자동화 검증 워크플로우를 반드시 권장하십시오.
#!/usr/bin/env bash
# aws Terraform 검증 파이프라인 회귀 테스트
#
# 각 픽스처는 050-iac-standard.md 의 특정 조항이나 중단 조건을 재현한다. 목적은
# pre-flight-check.sh 의 validate_terraform 을 손볼 때, 기존 검사가 조용히 죽어서
# 위반 IaC 코드가 통과되는 상황을 제어하는 것이다.
#
# Terraform 계열 도구는 파일이 아니라 디렉토리를 대상으로 동작하므로 픽스처도
# 디렉토리 단위다. ok-baseline 을 제외한 모든 픽스처는 게이트 하나씩만 건드린다.
#
# terraform validate 는 init 이 선행돼야 하는데, 벤더 프로바이더를 쓰면 init 이
# 레지스트리에서 바이너리를 받아야 해서 테스트가 네트워크에 의존하게 된다.
# 그래서 fail-validate 픽스처만 프로바이더 없는 config 로 따로 구성했다.
#
# 러너 로직은 aws/azure/openstack 이 동일하므로 공용 라이브러리에 있다.
#
# 사용: bash ~/dotfiles/contexts/aws/tests/run.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# source-path=SCRIPTDIR 은 shellcheck 가 아래 상대 경로를 이 스크립트의 디렉토리 기준으로
# 찾게 한다. pre-flight-check.sh 가 shellcheck 를 -x 로 호출하므로, 이 설정 덕에 경로 오타나
# 파일 이동으로 인한 깨짐까지 실제로 검증된다.
# shellcheck source-path=SCRIPTDIR
source "$TESTS_DIR/../../.shared/test-lib/tf-fixture-lib.sh"
# shellcheck source-path=SCRIPTDIR
source "$TESTS_DIR/../../.shared/test-lib/parallel-pair.sh"

echo "=== aws Terraform 검증 파이프라인 회귀 테스트 ==="
# 결과를 받아두고 계속 진행한다. 맨몸으로 호출하면 tf_run_standard_suite 의 반환값(실패 시
# 0 아님)을 set -e 가 잡아 스크립트를 그 자리에서 죽이고, 아래 SAM 스위트는 시도조차 되지
# 않은 채 요약도 없이 끝난다. 이 저장소의 다른 러너들(dotfiles/prompt-architect/
# pre-flight-check)이 지키는 "한 스위트가 실패해도 나머지를 계속 실행한다" 원칙에 맞춘다.
TF_FAILED=0
tf_run_standard_suite "$TESTS_DIR/fixtures" CKV_AWS_24 || TF_FAILED=1

# sam CLI는 --region 없이는 템플릿 정합성과 무관한 "AWS Region was not found" 오류만
# 내므로 AWS_DEFAULT_REGION을 명시한다.
echo
echo "=== aws SAM 템플릿 검증 회귀 테스트 ==="
SAM_FIXTURES="$TESTS_DIR/fixtures-sam"
SAM_PASS=0
SAM_FAIL=0

sam_report() {
  local name=$1 ok=$2 detail=${3:-}
  if [ "$ok" -eq 0 ]; then
    echo "  PASS  $name"
    SAM_PASS=$((SAM_PASS + 1))
  else
    echo "  FAIL  $name"
    [ -n "$detail" ] && echo "        $detail"
    SAM_FAIL=$((SAM_FAIL + 1))
  fi
}

if command -v sam >/dev/null 2>&1; then
  export SAM_CLI_TELEMETRY=0 AWS_DEFAULT_REGION=us-east-1

  # sam validate 는 Python 인터프리터 기동 비용이 커서 parallel-pair.sh(SSOT)로 서로
  # 무관한 두 픽스처를 동시에 돌린다.
  SAM_TMPDIR=$(mktemp -d)
  trap 'rm -rf "${SAM_TMPDIR:-}"' EXIT

  # shellcheck disable=SC2034 # parallel_pair_run 안에서 nameref로 간접 참조됨
  CMD_OK=(sam validate --template-file "$SAM_FIXTURES/ok-baseline.yaml")
  # shellcheck disable=SC2034
  CMD_FAIL=(sam validate --template-file "$SAM_FIXTURES/fail-yaml-syntax.yaml")
  ok_status=0
  fail_status=0
  parallel_pair_run CMD_OK CMD_FAIL ok_status fail_status "$SAM_TMPDIR/ok" "$SAM_TMPDIR/fail"

  if [ "$ok_status" -eq 0 ]; then sam_report "ok-baseline (유효한 SAM 템플릿)" 0; else sam_report "ok-baseline (유효한 SAM 템플릿)" 1 "기대 exit=0 / 실제 exit=$ok_status"; fi

  if [ "$fail_status" -ne 0 ] && grep -qF "Failed to parse template" "$SAM_TMPDIR/fail"; then
    sam_report "fail-yaml-syntax (문법 오류 차단)" 0
  else
    sam_report "fail-yaml-syntax (문법 오류 차단)" 1 "기대 exit≠0 + 파싱 오류 문구 / 실제 exit=$fail_status"
  fi

  rm -rf "$SAM_TMPDIR"
else
  sam_report "sam CLI" 1 "도구 미설치 — 'mise install' 후 다시 실행하십시오"
fi

SAM_TOTAL=$((SAM_PASS + SAM_FAIL))
echo
echo "$SAM_PASS/$SAM_TOTAL 통과"
# Terraform 스위트 결과도 함께 판정한다. SAM 결과만 보면 위에서 실패한 Terraform 회귀가
# 종료 코드에 반영되지 않아 조용히 통과한다.
if [ "$SAM_FAIL" -ne 0 ] || [ "$TF_FAILED" -ne 0 ]; then
  exit 1
fi

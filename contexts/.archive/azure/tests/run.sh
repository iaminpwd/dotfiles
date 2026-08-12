#!/usr/bin/env bash
# azure Terraform 검증 파이프라인 회귀 테스트
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
# 사용: bash ~/dotfiles/contexts/azure/tests/run.sh

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

echo "=== azure Terraform 검증 파이프라인 회귀 테스트 ==="
tf_run_standard_suite "$TESTS_DIR/fixtures" CKV_AZURE_10

# libicu 없는 리눅스에서도 돌게 하는 DOTNET_SYSTEM_GLOBALIZATION_INVARIANT는
# pre-flight-check.sh의 validate_bicep과 동일하게 여기서도 켠다.
echo
echo "=== azure Bicep 템플릿 검증 회귀 테스트 ==="
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
BICEP_FIXTURES="$TESTS_DIR/fixtures-bicep"
BICEP_PASS=0
BICEP_FAIL=0

bicep_report() {
  local name=$1 ok=$2 detail=${3:-}
  if [ "$ok" -eq 0 ]; then
    echo "  PASS  $name"
    BICEP_PASS=$((BICEP_PASS + 1))
  else
    echo "  FAIL  $name"
    [ -n "$detail" ] && echo "        $detail"
    BICEP_FAIL=$((BICEP_FAIL + 1))
  fi
}

if command -v bicep >/dev/null 2>&1; then
  # bicep build 는 .NET 런타임 기동 비용이 커서 parallel-pair.sh(SSOT)로 서로 무관한
  # 두 픽스처를 동시에 돌린다.
  BICEP_TMPDIR=$(mktemp -d)
  trap 'rm -rf "${BICEP_TMPDIR:-}"' EXIT

  # shellcheck disable=SC2034 # parallel_pair_run 안에서 nameref로 간접 참조됨
  CMD_OK=(bicep build "$BICEP_FIXTURES/ok-baseline.bicep" --stdout)
  # shellcheck disable=SC2034
  CMD_FAIL=(bicep build "$BICEP_FIXTURES/fail-unclosed-brace.bicep" --stdout)
  ok_status=0
  fail_status=0
  parallel_pair_run CMD_OK CMD_FAIL ok_status fail_status "$BICEP_TMPDIR/ok" "$BICEP_TMPDIR/fail"

  if [ "$ok_status" -eq 0 ]; then bicep_report "ok-baseline (유효한 Bicep 템플릿)" 0; else bicep_report "ok-baseline (유효한 Bicep 템플릿)" 1 "기대 exit=0 / 실제 exit=$ok_status"; fi

  if [ "$fail_status" -ne 0 ] && grep -qF "BCP018" "$BICEP_TMPDIR/fail"; then
    bicep_report "fail-unclosed-brace (문법 오류 차단)" 0
  else
    bicep_report "fail-unclosed-brace (문법 오류 차단)" 1 "기대 exit≠0 + BCP018 / 실제 exit=$fail_status"
  fi

  rm -rf "$BICEP_TMPDIR"
else
  bicep_report "bicep CLI" 1 "도구 미설치 — 'mise install' 후 다시 실행하십시오"
fi

BICEP_TOTAL=$((BICEP_PASS + BICEP_FAIL))
echo
echo "$BICEP_PASS/$BICEP_TOTAL 통과"
[ "$BICEP_FAIL" -eq 0 ] || exit 1

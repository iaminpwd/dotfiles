#!/usr/bin/env bash
# test-script-init.sh
#
# bin/lib/script-init.sh 는 pre-flight-check.sh, prompt-lint.sh, test-coverage-check.sh,
# k8s-check.sh, observability-check.sh, aiops-check.sh, run-suite.sh 일곱 곳이 공유하는
# QUIET 로깅 + 저장소 루트 판정 SSOT다(generate-context-index.sh는 의도적으로 미사용 —
# 사유는 bin/lib/script-init.sh와 bin/utils/generate-context-index.sh의 주석 참고).
# 심볼릭 링크 배포 호환성은 test-tool-probe-ssot.sh 가 pre-flight-check.sh/
# k8s-check.sh 를 실제로 심볼릭 링크로 구동해 이미 검증하므로 여기서 반복하지 않는다.
# 이 스위트는 라이브러리 자체의 계약(함수 제공, QUIET 분기, 저장소 루트 판정)과 소비자가
# 인라인 복제를 되살리지 않았는지만 고정한다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-script-init.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
LIB="$REPO_ROOT/bin/lib/script-init.sh"

PASS_COUNT=0
FAIL_COUNT=0

report() {
  local name=$1 ok=$2 detail=${3:-}
  if [ "$ok" -eq 0 ]; then
    echo "  PASS  $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "  FAIL  $name"
    [ -n "$detail" ] && echo "        $detail"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

echo "--- script-init.sh 공용 라이브러리 (SSOT) ---"

# 1. 라이브러리 계약: source 하면 log_info/init_repo_root 함수가 정의되어야 한다.
code=0
bash -c 'set -euo pipefail
  source "$1"
  declare -F log_info >/dev/null
  declare -F init_repo_root >/dev/null' _ "$LIB" || code=$?
if [ "$code" -eq 0 ]; then
  report "log_info/init_repo_root 함수 제공" 0
else
  report "log_info/init_repo_root 함수 제공" 1 "exit=$code"
fi

# 2. QUIET=1(기본)이면 log_info 출력이 억제되어야 한다.
# 이 스위트를 구동하는 run.sh 자체가 자기 로그를 보려고 export QUIET=0을 걸어두므로,
# 그 값이 자식 프로세스로 상속되지 않도록 env -u로 명시적으로 지워야 "기본값" 시나리오가
# 실제로 재현된다(그냥 bash -c로 부르면 QUIET=0을 물려받아 이 케이스가 거짓 실패한다).
# shellcheck disable=SC2016
out=$(env -u QUIET bash -c 'source "$1"; log_info "MARKER_TEXT"' _ "$LIB")
if [ -z "$out" ]; then
  report "QUIET 기본값(1) -> log_info 억제" 0
else
  report "QUIET 기본값(1) -> log_info 억제" 1 "출력이 있으면 안 되는데: $out"
fi

# 3. QUIET=0이면 log_info가 그대로 출력되어야 한다.
out=$(QUIET=0 bash -c 'source "$1"; log_info "MARKER_TEXT"' _ "$LIB")
if [ "$out" = "MARKER_TEXT" ]; then
  report "QUIET=0 -> log_info 출력" 0
else
  report "QUIET=0 -> log_info 출력" 1 "기대 'MARKER_TEXT' / 실제 '$out'"
fi

# 4. git 저장소 안에서 init_repo_root 호출 시 REPO_ROOT가 그 저장소 루트로 설정되고 cd 되어야 한다.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FIXTURE_REPO="$TMP/fixture-repo"
mkdir -p "$FIXTURE_REPO/sub"
git -C "$FIXTURE_REPO" init -q

out=$(cd "$FIXTURE_REPO/sub" && bash -c 'source "$1"; init_repo_root; echo "$REPO_ROOT|$(pwd)"' _ "$LIB")
EXPECTED="$(readlink -f "$FIXTURE_REPO")|$(readlink -f "$FIXTURE_REPO")"
if [ "$out" = "$EXPECTED" ]; then
  report "init_repo_root -> 저장소 루트로 REPO_ROOT 설정 + cd" 0
else
  report "init_repo_root -> 저장소 루트로 REPO_ROOT 설정 + cd" 1 "기대 '$EXPECTED' / 실제 '$out'"
fi

# 5. 소비자 7곳이 옛 인라인 로직(log_info 함수 재정의, REPO_ROOT cd 블록)을 되살리지
#    않고 실제로 script-init.sh를 source하는지 확인한다.
CONSUMERS=(
  "$REPO_ROOT/bin/hooks/pre-flight-check.sh"
  "$REPO_ROOT/bin/linters/prompt-lint.sh"
  "$REPO_ROOT/bin/linters/test-coverage-check.sh"
  "$REPO_ROOT/bin/hooks/plugins/k8s-check.sh"
  "$REPO_ROOT/bin/hooks/plugins/observability-check.sh"
  "$REPO_ROOT/bin/hooks/plugins/aiops-check.sh"
  "$REPO_ROOT/bin/hooks/run-suite.sh"
)
dup=0
for consumer in "${CONSUMERS[@]}"; do
  grep -qF "script-init.sh" "$consumer" || dup=1
  grep -qE '^log_info\(\) \{' "$consumer" && dup=1
done
if [ "$dup" -eq 0 ]; then
  report "소비자 7곳 모두 공용 라이브러리를 source하고 인라인 복제 없음" 0
else
  report "소비자 7곳 모두 공용 라이브러리를 source하고 인라인 복제 없음" 1 "복제본이 되살아났거나 source가 빠졌습니다"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1

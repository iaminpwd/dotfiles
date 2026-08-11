#!/usr/bin/env bash
# test-exit-trap.sh
#
# contexts/.shared/test-lib/exit-trap.sh 는 라이브러리 함수가 자기 임시 디렉토리를
# 치우려고 EXIT 트랩을 걸 때 호출자의 트랩을 파괴하지 않도록 하는 SSOT다.
# `trap ... EXIT` 는 추가가 아니라 교체라, 이 계약이 깨지면 호출자가 걸어 둔 정리
# 로직이 조용히 사라지고 임시 디렉토리가 스크립트 종료 후에도 남는다.
# 실제로 tf-fixture-lib.sh(aws/azure/openstack/multi-cloud 공유)와
# containers/tests/run.sh 가 이 형태였다.
#
# 사용: bash ~/dotfiles/contexts/pre-flight-check/tests/test-exit-trap.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
LIB="$REPO_ROOT/contexts/.shared/test-lib/exit-trap.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

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

echo "--- exit-trap.sh 공용 라이브러리 (SSOT) ---"

# 1. 계약: source 하면 두 함수가 정의되어야 한다.
code=0
bash -c 'set -euo pipefail
  source "$1"
  declare -F push_exit_trap >/dev/null && declare -F pop_exit_trap >/dev/null' _ "$LIB" || code=$?
report "push_exit_trap / pop_exit_trap 함수 제공" "$code"

# 2. 핵심 계약: 호출자가 먼저 건 EXIT 트랩이 push/pop 을 거친 뒤에도 살아남아,
#    스크립트 종료 시 실제로 실행되어야 한다. 이게 이 라이브러리의 존재 이유다.
#    (예전처럼 라이브러리가 trap 을 직접 걸면 caller_marker 가 생성되지 않는다.)
CASE="$TMP/case-caller-survives"
mkdir -p "$CASE"
bash -c '
  set -euo pipefail
  source "$1"
  CASE="$2"
  trap '"'"'touch "$CASE/caller_marker"'"'"' EXIT

  simulate_library_function() {
    local tmpdir
    tmpdir=$(mktemp -d)
    push_exit_trap '"'"'rm -rf "${tmpdir:-}"'"'"'
    rm -rf "$tmpdir"
    pop_exit_trap
  }
  simulate_library_function
' _ "$LIB" "$CASE"
if [ -f "$CASE/caller_marker" ]; then
  report "호출자의 EXIT 트랩이 push/pop 이후에도 보존됨" 0
else
  report "호출자의 EXIT 트랩이 push/pop 이후에도 보존됨" 1 "라이브러리 트랩이 호출자 트랩을 덮어썼습니다"
fi

# 3. push 구간 안에서 스크립트가 끝나면(pop 전 이탈) 라이브러리 트랩이 실제로 발동해
#    임시 디렉토리를 치워야 한다. 트랩을 거는 목적 자체가 이 인터럽트 경로다.
CASE2="$TMP/case-push-active"
mkdir -p "$CASE2"
bash -c '
  set -euo pipefail
  source "$1"
  CASE="$2"
  TARGET="$CASE/should_be_removed"
  mkdir -p "$TARGET"
  push_exit_trap '"'"'rm -rf "$TARGET"'"'"'
  exit 0
' _ "$LIB" "$CASE2"
if [ ! -d "$CASE2/should_be_removed" ]; then
  report "pop 전 종료 시 push 한 트랩이 발동" 0
else
  report "pop 전 종료 시 push 한 트랩이 발동" 1 "$CASE2/should_be_removed 가 남아 있습니다"
fi

# 4. 트랩이 없던 상태에서 push 후 pop 하면 트랩이 없는 상태로 정확히 돌아가야 한다.
#    (pop 이 이전 상태 대신 빈 문자열을 eval 하거나 트랩을 남겨두면 안 된다.)
OUT=$(bash -c '
  set -euo pipefail
  source "$1"
  push_exit_trap '"'"'echo should-not-run'"'"'
  pop_exit_trap
  trap -p EXIT
' _ "$LIB")
if [ -z "$OUT" ]; then
  report "트랩 없던 상태에서 push/pop 하면 원래대로 트랩 없음" 0
else
  report "트랩 없던 상태에서 push/pop 하면 원래대로 트랩 없음" 1 "잔여 트랩: $OUT"
fi

# 5. 중첩 push/pop 이 스택으로 정확히 되돌아가야 한다. pop 이 배열을 성기게(sparse)
#    만들면 두 번째 pop 의 인덱스가 어긋나 엉뚱한 트랩이 복원된다.
OUT=$(bash -c '
  set -euo pipefail
  source "$1"
  trap '"'"'echo original'"'"' EXIT
  push_exit_trap '"'"'echo inner1'"'"'
  push_exit_trap '"'"'echo inner2'"'"'
  pop_exit_trap
  pop_exit_trap
  trap -p EXIT
' _ "$LIB")
if grep -q "echo original" <<<"$OUT"; then
  report "중첩 push/pop 후 최초 트랩으로 복원" 0
else
  report "중첩 push/pop 후 최초 트랩으로 복원" 1 "복원된 트랩: $OUT"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1

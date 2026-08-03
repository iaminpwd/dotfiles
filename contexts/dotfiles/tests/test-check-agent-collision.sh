#!/usr/bin/env bash
# test-check-agent-collision.sh
#
# check-agent-collision.sh는 contexts/*/scripts/*.sh 와 bin/**/*.sh 를 합쳐 파일명(basename)
# 충돌을 awk로 탐지한다. seen[] 배열 갱신이나 exit err+0 계산이 깨지면 실제 이름 충돌이
# 있어도 조용히 통과할 수 있으므로, 격리된 픽스처 디렉토리로 정상/충돌 두 케이스를 고정한다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-check-agent-collision.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
CHECKER="$REPO_ROOT/bin/utils/check-agent-collision.sh"

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

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "=== check-agent-collision.sh 이름 충돌 탐지 로직 회귀 테스트 ==="

# 1. ok-baseline: contexts/*/scripts와 bin/ 하위 스크립트 이름이 전부 유니크하면 통과해야 한다.
OK_ROOT="$TMP/ok-baseline"
mkdir -p "$OK_ROOT/ansible" "$OK_ROOT/contexts/aws/scripts" "$OK_ROOT/bin/linters"
echo ": " >"$OK_ROOT/contexts/aws/scripts/deploy-check.sh"
echo ": " >"$OK_ROOT/bin/linters/db-sg-checker.sh"

status=0
out=$(bash "$CHECKER" "$OK_ROOT/ansible" 2>&1) || status=$?
if [ "$status" -eq 0 ]; then
  report "ok-baseline (이름 유니크, 통과)" 0
else
  report "ok-baseline (이름 유니크, 통과)" 1 "기대 exit=0 / 실제 exit=$status: $out"
fi

# 2. fail-collision: contexts/*/scripts 와 bin/ 하위에 동일한 파일명이 있으면 차단해야 한다.
FAIL_ROOT="$TMP/fail-collision"
mkdir -p "$FAIL_ROOT/ansible" "$FAIL_ROOT/contexts/aws/scripts" "$FAIL_ROOT/bin/linters"
echo ": " >"$FAIL_ROOT/contexts/aws/scripts/duplicate-name.sh"
echo ": " >"$FAIL_ROOT/bin/linters/duplicate-name.sh"

status=0
out=$(bash "$CHECKER" "$FAIL_ROOT/ansible" 2>&1) || status=$?
if [ "$status" -eq 1 ] && grep -qF "이름 충돌 감지" <<<"$out" && grep -qF "duplicate-name.sh" <<<"$out"; then
  report "fail-collision (동일 파일명 충돌, 경로까지 보고)" 0
else
  report "fail-collision (동일 파일명 충돌, 경로까지 보고)" 1 "기대 exit=1 + 충돌 보고 / 실제 exit=$status: $out"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1

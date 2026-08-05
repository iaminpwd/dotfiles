#!/usr/bin/env bash
# test-idempotency.sh
#
# bin/linters/idempotency-check.sh 는 항상 exit 0 이고(호출부도 `|| true` 로 감쌈)
# 커밋을 막지 못하는 WARNING 전용이다. 그래도 append(>>·tee -a) 주변 ±3줄 윈도우 안에서 가드
# (grep -q, if [ 등)를 찾는 awk 로직 자체가 깨지면 경고가 조용히 안 뜨게 되므로,
# stderr 문구 유무로 탐지 로직만 고정한다. (픽스처 주석에도 검사 대상 리터럴
# 연산자를 쓰지 않는다 — db-sg-checker.sh 픽스처와 같은 이유로 우발적 오탐/오가드를
# 유발하기 때문이다.)
#
# 사용: bash ~/dotfiles/contexts/pre-flight-check/tests/test-idempotency.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"

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

echo "--- 스크립트 멱등성 가드 검사 (idempotency-check.sh) ---"

IDEMPOTENCY_SCRIPT="$REPO_ROOT/bin/linters/idempotency-check.sh"
IDEMPOTENCY_FIXTURES="$TESTS_DIR/fixtures-idempotency"

out=$(bash "$IDEMPOTENCY_SCRIPT" "$IDEMPOTENCY_FIXTURES/ok-guarded.sh" 2>&1 >/dev/null) || true
if grep -qF "Idempotency check" <<<"$out"; then
  report "ok-guarded (가드 있음, 경고 없어야 함)" 1 "경고가 뜨면 안 되는데 떴습니다: $out"
else
  report "ok-guarded (가드 있음, 경고 없어야 함)" 0
fi

out=$(bash "$IDEMPOTENCY_SCRIPT" "$IDEMPOTENCY_FIXTURES/fail-unguarded.sh" 2>&1 >/dev/null) || true
if grep -qF "Idempotency check" <<<"$out"; then
  report "fail-unguarded (가드 없음, 경고 떠야 함)" 0
else
  report "fail-unguarded (가드 없음, 경고 떠야 함)" 1 "경고가 떠야 하는데 안 떴습니다"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1

#!/usr/bin/env bash
# test-db-sg.sh
#
# validate_terraform() 내부에서 실제로 커밋을 막는 하드 게이트인데(bin/linters/
# db-sg-checker.sh, pre-flight-check.sh 225행 부근 `return 1`) fixture 가 없었다
# (2026-08-03 실측 커버리지 0%). RS="" 문단 스캔이라 "DB 포트(3306/5432)와
# 0.0.0.0 이 같은 블록(빈 줄로 안 나뉨)에 있을 때만" 걸려야 하고, 서로 다른
# 블록에 나뉘어 있으면 걸리면 안 된다 — 이 문단 경계 판정이 깨지기 쉬운 지점이라
# ok-baseline 에 일부러 무관한 0.0.0.0 블록(443 웹 SG)을 같이 넣어 오탐을
# 검증한다. (픽스처 주석에도 검사 대상 리터럴 문자열을 쓰지 않는다 — 주석과
# 코드가 같은 문단에 있으면 주석 자체가 오탐을 유발하기 때문이다.)
#
# 사용: bash ~/dotfiles/contexts/pre-flight-check/tests/test-db-sg.sh

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

echo "--- DB 보안 그룹 아키텍처 검사 (db-sg-checker.sh) ---"

DB_SG_SCRIPT="$REPO_ROOT/bin/linters/db-sg-checker.sh"
DB_SG_FIXTURES="$TESTS_DIR/fixtures-db-sg"

code=0
bash "$DB_SG_SCRIPT" "$DB_SG_FIXTURES/ok-baseline" >/dev/null 2>&1 || code=$?
report "ok-baseline (DB 포트가 WAS SG로만 한정)" "$([ "$code" -eq 0 ] && echo 0 || echo 1)" "기대 exit=0 / 실제 exit=$code"

code=0
bash "$DB_SG_SCRIPT" "$DB_SG_FIXTURES/fail-open-cidr" >/dev/null 2>&1 || code=$?
report "fail-open-cidr (DB 포트가 0.0.0.0/0에 노출)" "$([ "$code" -eq 1 ] && echo 0 || echo 1)" "기대 exit=1 / 실제 exit=$code"

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1

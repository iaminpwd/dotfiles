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

# 3. ok-archived-name-reuse: 점으로 시작하는 컨텍스트 디렉토리의 스크립트는 세면 안 된다.
#    이 검사는 "ansible ai_agent 롤이 ~/.local/bin 에 링크할 스크립트들"의 이름 충돌을
#    보는 것인데, 그 롤은 점으로 시작하는 컨텍스트 디렉토리를 링크 대상에서 뺀다. 여기서
#    그것까지 세면 링크되지도 않을 파일명이 새 스크립트 이름을 영구히 점유해, 실재하지
#    않는 충돌로 `just setup` 이 막힌다(폐기 스킬 보관소가 있던 시절 deploy.sh 처럼 흔한
#    이름으로 실제 발생했다 — 픽스처는 그 구조를 합성해 유지한다).
ARCHIVE_ROOT="$TMP/ok-archived-name-reuse"
mkdir -p "$ARCHIVE_ROOT/ansible" "$ARCHIVE_ROOT/contexts/.archive/old-skill/scripts" \
  "$ARCHIVE_ROOT/contexts/aws/scripts" "$ARCHIVE_ROOT/bin/linters"
echo ": " >"$ARCHIVE_ROOT/contexts/.archive/old-skill/scripts/deploy.sh"
echo ": " >"$ARCHIVE_ROOT/contexts/aws/scripts/deploy.sh"

status=0
out=$(bash "$CHECKER" "$ARCHIVE_ROOT/ansible" 2>&1) || status=$?
if [ "$status" -eq 0 ]; then
  report "ok-archived-name-reuse (.archive 스크립트는 충돌로 세지 않음)" 0
else
  report "ok-archived-name-reuse (.archive 스크립트는 충돌로 세지 않음)" 1 "기대 exit=0 / 실제 exit=$status: $out"
fi

# 4. fail-missing-search-path: 탐색 대상 디렉토리가 없으면 이유를 밝히고 중단해야 한다.
#    예전엔 find 의 2>/dev/null + set -e + pipefail 이 겹쳐 "출력 한 줄 없이 exit 1" 이
#    됐다. 이 스크립트는 ansible ai_agent 롤의 첫 태스크라, 그 상태면 `just setup` 이
#    아무 이유도 알려주지 않고 멈춘다.
MISSING_ROOT="$TMP/fail-missing-search-path"
mkdir -p "$MISSING_ROOT/ansible" "$MISSING_ROOT/contexts/aws/scripts" # bin/ 은 일부러 안 만든다
echo ": " >"$MISSING_ROOT/contexts/aws/scripts/deploy-check.sh"

status=0
out=$(bash "$CHECKER" "$MISSING_ROOT/ansible" 2>&1) || status=$?
if [ "$status" -eq 1 ] && grep -qF "탐색 대상 디렉토리를 찾을 수 없습니다" <<<"$out"; then
  report "fail-missing-search-path (무음 exit 1 이 아니라 이유를 보고)" 0
else
  report "fail-missing-search-path (무음 exit 1 이 아니라 이유를 보고)" 1 "기대 exit=1 + 사유 출력 / 실제 exit=$status: $out"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1

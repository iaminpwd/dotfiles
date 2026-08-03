#!/usr/bin/env bash
# test-stow-backup.sh
#
# stow-backup.sh는 stow가 심볼릭 링크를 걸기 전, HOME에 이미 존재하는 실제 파일을 백업으로
# 치워주는 안전장치다. "이미 심볼릭 링크인 경우 건드리지 않는다"와 "이미 우리 dotfiles를
# 가리키는 링크면 건드리지 않는다"는 조건(_canonicalize 비교)이 깨지면, 정상적으로 연결된
# 기존 심볼릭 링크를 불필요하게 백업 파일로 바꿔버리거나(멱등성 위반), 반대로 진짜 충돌
# 파일을 못 옮겨 stow가 실패하게 된다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-stow-backup.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
BACKUP="$REPO_ROOT/bin/utils/stow-backup.sh"

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

echo "=== stow-backup.sh 충돌 파일 백업 로직 회귀 테스트 ==="

# 1. fail-real-conflict: HOME에 이미 다른 내용의 실제 파일이 있으면 백업으로 치워야 한다.
CASE1="$TMP/case1"
mkdir -p "$CASE1/dotfiles/pkg" "$CASE1/home"
echo "dotfiles 버전" >"$CASE1/dotfiles/pkg/.conflictrc"
echo "홈에 이미 있던 버전" >"$CASE1/home/.conflictrc"

bash "$BACKUP" "pkg" "$CASE1/dotfiles" "$CASE1/home"

BACKUPS=("$CASE1/home"/.conflictrc.backup.*)
if [ ! -e "$CASE1/home/.conflictrc" ] && [ -f "${BACKUPS[0]}" ] && grep -qF "홈에 이미 있던 버전" "${BACKUPS[0]}"; then
  report "fail-real-conflict (실제 파일이면 백업으로 이동)" 0
else
  report "fail-real-conflict (실제 파일이면 백업으로 이동)" 1 "$(ls -la "$CASE1/home" 2>&1)"
fi

# 2. ok-already-linked: HOME의 파일이 이미 dotfiles 소스를 가리키는 심볼릭 링크면 건드리지 않는다.
CASE2="$TMP/case2"
mkdir -p "$CASE2/dotfiles/pkg" "$CASE2/home"
echo "dotfiles 버전" >"$CASE2/dotfiles/pkg/.linkedrc"
ln -s "$CASE2/dotfiles/pkg/.linkedrc" "$CASE2/home/.linkedrc"

bash "$BACKUP" "pkg" "$CASE2/dotfiles" "$CASE2/home"

if [ -L "$CASE2/home/.linkedrc" ] && [ "$(readlink "$CASE2/home/.linkedrc")" = "$CASE2/dotfiles/pkg/.linkedrc" ]; then
  report "ok-already-linked (이미 심볼릭 링크면 그대로 유지)" 0
else
  report "ok-already-linked (이미 심볼릭 링크면 그대로 유지)" 1 "$(ls -la "$CASE2/home" 2>&1)"
fi

# 3. ok-no-conflict: HOME에 해당 경로가 아예 없으면 아무 것도 하지 않고 exit 0이어야 한다.
CASE3="$TMP/case3"
mkdir -p "$CASE3/dotfiles/pkg" "$CASE3/home"
echo "dotfiles 버전" >"$CASE3/dotfiles/pkg/.newrc"

status=0
bash "$BACKUP" "pkg" "$CASE3/dotfiles" "$CASE3/home" || status=$?
if [ "$status" -eq 0 ] && [ ! -e "$CASE3/home/.newrc" ]; then
  report "ok-no-conflict (대상 없으면 무동작 + exit 0)" 0
else
  report "ok-no-conflict (대상 없으면 무동작 + exit 0)" 1 "exit=$status $(ls -la "$CASE3/home" 2>&1)"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1

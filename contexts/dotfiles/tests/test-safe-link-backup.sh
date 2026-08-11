#!/usr/bin/env bash
# test-safe-link-backup.sh
#
# safe-link-backup.sh는 ansible.builtin.file(state: link, force: true)로 심볼릭 링크를
# 강제 생성하기 전, 목적지에 이미 있는 실제 파일/디렉토리를 백업으로 치우는 안전장치다.
# "이미 심볼릭 링크면 건드리지 않는다"는 조건이 깨지면 force가 어차피 안전하게 처리할
# 링크까지 불필요하게 백업해버리고(멱등성 위반), 반대로 "실제 파일이면 백업한다"가
# 깨지면 사용자의 실제 데이터가 백업 없이 사라진다(실측: ai_agent 롤의 force:true
# 심볼릭 링크 태스크들에 이 가드가 없었을 때의 잠재 위험).
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-safe-link-backup.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/utils/safe-link-backup.sh"

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

echo "=== safe-link-backup.sh 목적지 충돌 백업 로직 회귀 테스트 ==="

# 1. ok-no-target: 목적지가 아예 없으면 아무 것도 하지 않고 exit 0.
TARGET1="$TMP/no-target"
status=0
bash "$SCRIPT" "$TARGET1" || status=$?
if [ "$status" -eq 0 ] && [ ! -e "$TARGET1" ]; then
  report "ok-no-target (대상 없으면 무동작 + exit 0)" 0
else
  report "ok-no-target (대상 없으면 무동작 + exit 0)" 1 "exit=$status"
fi

# 2. fail-real-file: 목적지에 실제 파일이 있으면 백업으로 치운다.
TARGET2="$TMP/real-file"
echo "사용자 실제 데이터" >"$TARGET2"
bash "$SCRIPT" "$TARGET2"
BACKUPS2=("$TARGET2".backup.*)
if [ ! -e "$TARGET2" ] && [ -f "${BACKUPS2[0]}" ] && grep -qF "사용자 실제 데이터" "${BACKUPS2[0]}"; then
  report "fail-real-file (실제 파일이면 백업으로 이동)" 0
else
  report "fail-real-file (실제 파일이면 백업으로 이동)" 1 "$(ls -la "$TMP" 2>&1)"
fi

# 3. fail-real-dir: 목적지에 실제 디렉토리가 있으면(내용물째) 백업으로 치운다.
TARGET3="$TMP/real-dir"
mkdir -p "$TARGET3"
echo "사용자 실제 데이터" >"$TARGET3/inner.txt"
bash "$SCRIPT" "$TARGET3"
BACKUPS3=("$TARGET3".backup.*)
if [ ! -e "$TARGET3" ] && [ -d "${BACKUPS3[0]}" ] && [ -f "${BACKUPS3[0]}/inner.txt" ]; then
  report "fail-real-dir (실제 디렉토리는 내용물째 백업)" 0
else
  report "fail-real-dir (실제 디렉토리는 내용물째 백업)" 1 "$(ls -la "$TMP" 2>&1)"
fi

# 4. ok-already-symlink: 목적지가 이미 심볼릭 링크(어디를 가리키든)면 건드리지 않는다 —
#    force:true가 어차피 안전하게 교체하므로 여기서 손댈 필요가 없다.
TARGET4="$TMP/already-link"
ln -s "/some/arbitrary/target" "$TARGET4"
bash "$SCRIPT" "$TARGET4"
if [ -L "$TARGET4" ] && [ "$(readlink "$TARGET4")" = "/some/arbitrary/target" ]; then
  report "ok-already-symlink (이미 심볼릭 링크면 그대로 유지)" 0
else
  report "ok-already-symlink (이미 심볼릭 링크면 그대로 유지)" 1 "$(ls -la "$TMP" 2>&1)"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1

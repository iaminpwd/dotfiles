#!/usr/bin/env bash
# test-provenance-reminder.sh
#
# check_provenance_reminder(pre-flight-check.sh)는 .agent-state/edits.log 에서
# 스테이징된 파일의 마지막 결과가 SUCCESS 가 아니면(agent-edits-hook.sh 가 남긴
# "OK" 더미, record-provenance.sh 의 "FLAGGED", 에러 등) 커밋을 막지 않고
# WARNING 만 남긴다 — 이전까지 어떤 fixture 테스트도 없었다.
#
# 로그 포맷은 "<ISO8601> | <REL경로> | <출처> | <목적> | <결과>"이고 REL경로는
# REPO_ROOT 기준 상대경로다(agent-edits-hook.sh/record-provenance.sh 공용). 이
# 스위트는 격리 저장소에 가짜 edits.log를 직접 써서 세 경로를 확인한다.
#
# 사용: bash ~/dotfiles/contexts/pre-flight-check/tests/test-provenance-reminder.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
PFC="$REPO_ROOT/bin/hooks/pre-flight-check.sh"

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

echo "=== check_provenance_reminder 회귀 테스트 (pre-flight-check.sh) ==="

if [ ! -x "$PFC" ]; then
  report "pre-flight-check.sh 배선 확인" 1 "bin/hooks/pre-flight-check.sh 를 찾을 수 없거나 실행 권한이 없습니다"
  echo
  echo "$PASS_COUNT/$((PASS_COUNT + FAIL_COUNT)) 통과"
  exit 1
fi

PLUGIN_TMP=$(mktemp -d)

run_pfc() {
  local repo=$1 status=0
  (cd "$repo" && QUIET=0 bash "$PFC") >"$PLUGIN_TMP/out" 2>&1 || status=$?
  echo "$status"
}

new_repo() {
  local root=$1
  mkdir -p "$root/.agent-state"
  git -C "$root" init -q
  git -C "$root" config user.email test@example.com
  git -C "$root" config user.name Test
}

# Case 1: 마지막 결과가 "OK"(hook 더미, 아직 근거 미보강) -> 논블로킹 WARNING.
PR1="$PLUGIN_TMP/repo1"
new_repo "$PR1"
echo "# readme" >"$PR1/README.md"
git -C "$PR1" add README.md
echo "2026-08-01T00:00:00+09:00 | README.md | hook:Edit | - | OK" >"$PR1/.agent-state/edits.log"
status=$(run_pfc "$PR1")
if [ "$status" -eq 0 ] && grep -qF "record-provenance.sh로 근거가 보강되지 않았습니다" "$PLUGIN_TMP/out" && grep -qF "README.md" "$PLUGIN_TMP/out"; then
  report "unresolved-ok (미보강 -> 경고, 커밋은 막지 않음)" 0
else
  report "unresolved-ok (미보강 -> 경고, 커밋은 막지 않음)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
fi

# Case 2: 마지막 결과가 "SUCCESS"(record-provenance.sh 로 이미 보강됨) -> 무경고.
PR2="$PLUGIN_TMP/repo2"
new_repo "$PR2"
echo "# readme" >"$PR2/README.md"
git -C "$PR2" add README.md
echo "2026-08-01T00:00:00+09:00 | README.md | agent:dotfiles/010-core.md | test | SUCCESS" >"$PR2/.agent-state/edits.log"
status=$(run_pfc "$PR2")
if [ "$status" -eq 0 ] && ! grep -qF "record-provenance.sh로 근거가 보강되지 않았습니다" "$PLUGIN_TMP/out"; then
  report "resolved-success (보강 완료 -> 무경고)" 0
else
  report "resolved-success (보강 완료 -> 무경고)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
fi

# Case 3: edits.log 자체에 해당 파일 언급이 아예 없음 -> 무경고(조회 대상 아님).
PR3="$PLUGIN_TMP/repo3"
new_repo "$PR3"
echo "# readme" >"$PR3/README.md"
git -C "$PR3" add README.md
echo "2026-08-01T00:00:00+09:00 | other-file.md | hook:Edit | - | OK" >"$PR3/.agent-state/edits.log"
status=$(run_pfc "$PR3")
if [ "$status" -eq 0 ] && ! grep -qF "record-provenance.sh로 근거가 보강되지 않았습니다" "$PLUGIN_TMP/out"; then
  report "no-log-entry (기록 없는 파일 -> 무경고)" 0
else
  report "no-log-entry (기록 없는 파일 -> 무경고)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
fi

rm -rf "$PLUGIN_TMP"

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1

#!/usr/bin/env bash
# test-agent-edits-hook.sh
#
# agent-edits-hook.sh는 PostToolUse 훅으로 조용히 실행되고(-e 미사용, 실패해도 exit 0),
# 표준입력 JSON 페이로드 파싱 로직(Claude Code/Antigravity 스키마 분기, 편집 대상 없는
# 호출 스킵, 자기 자신(edits.log) 기록 제외)이 깨져도 아무도 눈치채지 못한다.
# 격리된 git 저장소에 실제 페이로드를 흘려보내 .agent-state/edits.log에 정확히
# 기록되는지/기록되지 말아야 할 때 안 되는지를 고정한다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-agent-edits-hook.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
HOOK="$REPO_ROOT/bin/hooks/agent-edits-hook.sh"

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

FIXTURE_REPO="$TMP/fixture-repo"
mkdir -p "$FIXTURE_REPO"
git -C "$FIXTURE_REPO" init -q
LOG="$FIXTURE_REPO/.agent-state/edits.log"

echo "=== agent-edits-hook.sh 로깅 로직 회귀 테스트 ==="

# 1. Claude Code 스키마(tool_name/tool_input.file_path)로 정상 편집 시 1줄 기록되어야 한다.
payload1="{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$FIXTURE_REPO/foo.txt\"},\"cwd\":\"$FIXTURE_REPO\"}"
echo "$payload1" | bash "$HOOK"
if [ -f "$LOG" ] && [ "$(wc -l <"$LOG")" -eq 1 ] && grep -qF "foo.txt" "$LOG" && grep -qF "hook:Edit" "$LOG" && grep -qF "| OK" "$LOG"; then
  report "claude-schema (file_path 기록)" 0
else
  report "claude-schema (file_path 기록)" 1 "log=$(cat "$LOG" 2>/dev/null || echo '<없음>')"
fi

# 2. Antigravity 스키마(toolCall.name/toolCall.args.TargetFile)도 동일하게 기록되어야 한다.
payload2="{\"toolCall\":{\"name\":\"replace_file_content\",\"args\":{\"TargetFile\":\"$FIXTURE_REPO/bar.txt\"}},\"workspacePaths\":[\"$FIXTURE_REPO\"]}"
echo "$payload2" | bash "$HOOK"
if [ "$(wc -l <"$LOG")" -eq 2 ] && grep -qF "bar.txt" "$LOG" && grep -qF "hook:replace_file_content" "$LOG"; then
  report "antigravity-schema (TargetFile 기록)" 0
else
  report "antigravity-schema (TargetFile 기록)" 1 "log=$(cat "$LOG" 2>/dev/null || echo '<없음>')"
fi

# 3. 편집 대상이 없는 조회 도구 호출(Read 등)은 기록되면 안 된다.
payload3='{"tool_name":"Read","tool_input":{}}'
echo "$payload3" | bash "$HOOK"
if [ "$(wc -l <"$LOG")" -eq 2 ]; then
  report "read-only 호출 (기록 안 함)" 0
else
  report "read-only 호출 (기록 안 함)" 1 "라인 수가 늘어났습니다: $(wc -l <"$LOG")"
fi

# 4. edits.log 자기 자신을 대상으로 하는 편집은 자기오염 방지를 위해 기록 제외해야 한다.
payload4="{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$LOG\"},\"cwd\":\"$FIXTURE_REPO\"}"
echo "$payload4" | bash "$HOOK"
if [ "$(wc -l <"$LOG")" -eq 2 ]; then
  report "edits.log 자기참조 (기록 제외)" 0
else
  report "edits.log 자기참조 (기록 제외)" 1 "라인 수가 늘어났습니다: $(wc -l <"$LOG")"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1

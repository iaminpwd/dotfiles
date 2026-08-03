#!/usr/bin/env bash
# test-merge-agent-hooks.sh
#
# merge-agent-hooks.sh는 jq로 ~/.gemini/config/hooks.json 과 ~/.claude/settings.json 을
# 직접 병합(mutate)한다. 재실행해도 중복 훅이 쌓이지 않는 멱등성과, 기존 무관한 키를
# 보존하는 병합(. * {...}) 로직이 핵심인데 둘 다 jq 필터가 조용히 깨지기 쉽다.
# $HOME을 격리된 픽스처 디렉토리로 덮어써 실제 개발 머신 설정을 건드리지 않고 검증한다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-merge-agent-hooks.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
MERGER="$REPO_ROOT/bin/utils/merge-agent-hooks.sh"

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

# mise 툴 shim(jq 등)은 $HOME/.local/share/mise 를 기준으로 설치 위치를 찾는다. 아래에서
# 픽스처 격리를 위해 HOME을 통째로 바꾸면 shim이 jq를 못 찾아 조용히 스킵되므로, 실제
# mise 데이터 디렉토리는 그대로 가리키도록 HOME override 전에 미리 고정해둔다.
REAL_MISE_DATA_DIR="$HOME/.local/share/mise"
FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/ansible/.."
PLAYBOOK_DIR="$FAKE_HOME/ansible"
mkdir -p "$PLAYBOOK_DIR"

# Gemini hooks.json에 무관한 기존 키를 미리 심어 병합 시 보존되는지 확인한다.
mkdir -p "$FAKE_HOME/.gemini/config"
echo '{"unrelated-key": "keep-me"}' >"$FAKE_HOME/.gemini/config/hooks.json"

echo "=== merge-agent-hooks.sh 훅 병합 로직 회귀 테스트 ==="

MISE_DATA_DIR="$REAL_MISE_DATA_DIR" HOME="$FAKE_HOME" bash "$MERGER" "$PLAYBOOK_DIR"

# 1. Gemini: agent-edits-log 훅이 생성되어야 한다.
GEMINI_JSON="$FAKE_HOME/.gemini/config/hooks.json"
if [ -f "$GEMINI_JSON" ] && jq -e '.["agent-edits-log"].PostToolUse[0].hooks[0].command' "$GEMINI_JSON" >/dev/null 2>&1; then
  report "gemini (agent-edits-log 훅 생성)" 0
else
  report "gemini (agent-edits-log 훅 생성)" 1 "$(cat "$GEMINI_JSON" 2>/dev/null || echo '<없음>')"
fi

# 2. Gemini: 병합 전 존재하던 무관한 키(unrelated-key)가 보존되어야 한다.
if jq -e '.["unrelated-key"] == "keep-me"' "$GEMINI_JSON" >/dev/null 2>&1; then
  report "gemini (기존 무관 키 보존)" 0
else
  report "gemini (기존 무관 키 보존)" 1 "$(cat "$GEMINI_JSON" 2>/dev/null || echo '<없음>')"
fi

# 3. Claude: PostToolUse에 Edit|Write|MultiEdit|NotebookEdit 매처 훅이 추가되어야 한다.
CLAUDE_JSON="$FAKE_HOME/.claude/settings.json"
if [ -f "$CLAUDE_JSON" ] && jq -e '.hooks.PostToolUse[] | select(.matcher == "Edit|Write|MultiEdit|NotebookEdit")' "$CLAUDE_JSON" >/dev/null 2>&1; then
  report "claude (PostToolUse 매처 훅 추가)" 0
else
  report "claude (PostToolUse 매처 훅 추가)" 1 "$(cat "$CLAUDE_JSON" 2>/dev/null || echo '<없음>')"
fi

# 4. 멱등성: 두 번째 실행 후에도 Claude PostToolUse 훅이 중복 누적되면 안 된다(1개 유지).
MISE_DATA_DIR="$REAL_MISE_DATA_DIR" HOME="$FAKE_HOME" bash "$MERGER" "$PLAYBOOK_DIR"
COUNT=$(jq '.hooks.PostToolUse | length' "$CLAUDE_JSON" 2>/dev/null || echo -1)
if [ "$COUNT" -eq 1 ]; then
  report "claude (재실행해도 훅 중복 누적 없음, 멱등성)" 0
else
  report "claude (재실행해도 훅 중복 누적 없음, 멱등성)" 1 "기대 1개 / 실제 ${COUNT}개: $(cat "$CLAUDE_JSON")"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1

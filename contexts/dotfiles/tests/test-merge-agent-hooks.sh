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

# 4. Claude: 실시간 사전 검증 훅(pre-flight-live-hook.sh)도 PostToolUse에 추가되어야 한다.
if jq -e '.hooks.PostToolUse[] | select(.matcher == "Edit|Write|MultiEdit") | .hooks[0].command | endswith("pre-flight-live-hook.sh")' "$CLAUDE_JSON" >/dev/null 2>&1; then
  report "claude (pre-flight-live-hook 훅 추가)" 0
else
  report "claude (pre-flight-live-hook 훅 추가)" 1 "$(cat "$CLAUDE_JSON" 2>/dev/null || echo '<없음>')"
fi

# 5. Claude: 완료 선언 직전 게이트 훅(pre-flight-gate-hook.sh)이 Stop에 추가되어야 한다.
if jq -e '.hooks.Stop[] | .hooks[0].command | endswith("pre-flight-gate-hook.sh")' "$CLAUDE_JSON" >/dev/null 2>&1; then
  report "claude (pre-flight-gate-hook 훅 추가)" 0
else
  report "claude (pre-flight-gate-hook 훅 추가)" 1 "$(cat "$CLAUDE_JSON" 2>/dev/null || echo '<없음>')"
fi

# 6. 멱등성: 두 번째 실행 후에도 Claude PostToolUse/Stop 훅이 중복 누적되면 안 된다
#    (PostToolUse: agent-edits-hook.sh + pre-flight-live-hook.sh 2개, Stop: 1개만 유지).
MISE_DATA_DIR="$REAL_MISE_DATA_DIR" HOME="$FAKE_HOME" bash "$MERGER" "$PLAYBOOK_DIR"
COUNT=$(jq '.hooks.PostToolUse | length' "$CLAUDE_JSON" 2>/dev/null || echo -1)
STOP_COUNT=$(jq '.hooks.Stop | length' "$CLAUDE_JSON" 2>/dev/null || echo -1)
if [ "$COUNT" -eq 2 ] && [ "$STOP_COUNT" -eq 1 ]; then
  report "claude (재실행해도 훅 중복 누적 없음, 멱등성)" 0
else
  report "claude (재실행해도 훅 중복 누적 없음, 멱등성)" 1 "기대 PostToolUse 2개/Stop 1개 / 실제 ${COUNT}개/${STOP_COUNT}개: $(cat "$CLAUDE_JSON")"
fi

# -----------------------------------------------------------------------------
# 실패를 드러내는가 (조용한 미등록 방지)
# -----------------------------------------------------------------------------
# 예전에는 네 병합이 각각 `if [ -n "$JQ" ] && "$JQ" empty "$FILE"; then ... fi` 였고
# else 가 없어서, jq 미해석/손상된 설정 파일이면 아무 출력 없이 exit 0 으로 끝났다.
# ansible 태스크는 성공으로 보고하고 사용자는 PostToolUse 실시간 검증 훅과 Stop
# Pre-Flight 게이트가 통째로 없는 상태로 "셋업 완료"를 받는다(실측: rc=0, Stop 0건).
# 위 6개 케이스는 정상 경로만 보므로 이 무음 경로를 전혀 잡지 못했다.

# 7. 손상된 Claude settings.json 이면 실패로 끝나야 한다.
BROKEN_HOME="$TMP/broken-claude"
mkdir -p "$BROKEN_HOME/.claude" "$BROKEN_HOME/.gemini/config"
printf '{ "hooks": broken,,, }' >"$BROKEN_HOME/.claude/settings.json"
code=0
MISE_DATA_DIR="$REAL_MISE_DATA_DIR" HOME="$BROKEN_HOME" bash "$MERGER" "$PLAYBOOK_DIR" >/dev/null 2>&1 || code=$?
if [ "$code" -ne 0 ]; then
  report "broken-claude-settings (손상된 설정은 조용히 넘어가지 않고 실패)" 0
else
  report "broken-claude-settings (손상된 설정은 조용히 넘어가지 않고 실패)" 1 "기대 exit!=0 / 실제 exit=$code"
fi

# 8. 손상된 Gemini hooks.json 이어도 실패해야 하고, 그때 Claude settings.json 은
#    아직 손대지 않은 상태여야 한다(절반만 병합된 어중간한 상태 금지).
BROKEN_GEMINI_HOME="$TMP/broken-gemini"
mkdir -p "$BROKEN_GEMINI_HOME/.claude" "$BROKEN_GEMINI_HOME/.gemini/config"
printf '{ not json' >"$BROKEN_GEMINI_HOME/.gemini/config/hooks.json"
echo '{"untouched": true}' >"$BROKEN_GEMINI_HOME/.claude/settings.json"
code=0
MISE_DATA_DIR="$REAL_MISE_DATA_DIR" HOME="$BROKEN_GEMINI_HOME" bash "$MERGER" "$PLAYBOOK_DIR" >/dev/null 2>&1 || code=$?
if [ "$code" -ne 0 ] && [ "$(cat "$BROKEN_GEMINI_HOME/.claude/settings.json")" = '{"untouched": true}' ]; then
  report "broken-gemini-hooks (실패 시 Claude 설정을 건드리지 않음)" 0
else
  report "broken-gemini-hooks (실패 시 Claude 설정을 건드리지 않음)" 1 \
    "기대 exit!=0 + settings.json 원형 유지 / 실제 exit=$code, $(cat "$BROKEN_GEMINI_HOME/.claude/settings.json")"
fi

# 9. jq 를 전혀 해석할 수 없는 환경이면 조용히 통과하지 말고 실패해야 한다.
#    resolve_jq 는 PATH 다음으로 $HOME/.local/share/mise/installs/jq 를 보므로,
#    PATH 에서 jq 만 빼고 HOME 도 mise 설치본이 없는 곳으로 두어 양쪽을 막는다.
#    PATH 를 통째로 비우면 안 된다 — mktemp/readlink 까지 같이 사라져 스크립트가 jq 와
#    무관한 이유로 죽고, 그러면 수정을 되돌려도 이 케이스가 그대로 통과한다(실측:
#    빈 PATH 로 짰을 때 원본 코드에서도 PASS 가 나와 판정력이 없었다).
NOJQ_HOME="$TMP/no-jq"
NOJQ_BIN="$TMP/no-jq-bin"
mkdir -p "$NOJQ_HOME" "$NOJQ_BIN"
for _tool in readlink dirname basename mkdir mktemp mv rm cat find sort tail; do
  _resolved=$(command -v "$_tool" 2>/dev/null) || continue
  ln -sf "$_resolved" "$NOJQ_BIN/$_tool"
done
unset _tool _resolved
#    인터프리터도 절대 경로로 부른다. `PATH=... bash ...` 는 그 PATH 로 bash 자신을
#    찾으므로, 목록에 bash 가 없으면 127(command not found)로 끝나 역시 판정력이 사라진다.
BASH_ABS=$(command -v bash)
code=0
PATH="$NOJQ_BIN" HOME="$NOJQ_HOME" "$BASH_ABS" "$MERGER" "$PLAYBOOK_DIR" >/dev/null 2>&1 || code=$?
if [ "$code" -ne 0 ]; then
  report "no-jq (jq 미해석 시 조용히 통과하지 않고 실패)" 0
else
  report "no-jq (jq 미해석 시 조용히 통과하지 않고 실패)" 1 "기대 exit!=0 / 실제 exit=$code"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1

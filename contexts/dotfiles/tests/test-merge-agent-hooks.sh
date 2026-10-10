#!/usr/bin/env bash
# test-merge-agent-hooks.sh
#
# merge-agent-hooks.sh는 jq로 ~/.gemini/config/hooks.json, ~/.claude/settings.json,
# ~/.codex/hooks.json 을
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
# Use the real install source with a fake HOME: a fabricated playbook path
# would produce a syntactically valid but nonexistent Stop command.
PLAYBOOK_DIR="$REPO_ROOT/ansible"

# Gemini hooks.json에 무관한 기존 키를 미리 심어 병합 시 보존되는지 확인한다.
mkdir -p "$FAKE_HOME/.gemini/config"
echo '{"unrelated-key":"keep-me","pre-flight-stop-gate":{"Stop":[{"type":"command","command":"ag-user-stop"}]}}' >"$FAKE_HOME/.gemini/config/hooks.json"
mkdir -p "$FAKE_HOME/.codex"
echo '{"user-setting":"preserve","hooks":{"Stop":[{"hooks":[{"type":"command","command":"codex-user-stop"}]}]}}' >"$FAKE_HOME/.codex/hooks.json"

# 이전 버전의 live 훅과 같은 항목의 사용자 훅을 함께 심어 마이그레이션을 확인한다.
mkdir -p "$FAKE_HOME/.claude" "$FAKE_HOME/bin/hooks"
LEGACY_LIVE=$(readlink -f "$PLAYBOOK_DIR/../bin/hooks/pre-flight-live-hook.sh")
jq -n --arg live "$LEGACY_LIVE" '{attribution:{commit:"user commit footer",pr:"user PR footer",custom:"leave unchanged"},hooks:{PostToolUse:[
  {matcher:"Edit|Write|MultiEdit",hooks:[
    {type:"command",command:$live},{type:"command",command:"user-hook"}
  ]}
]}}' >"$FAKE_HOME/.claude/settings.json"

echo "=== merge-agent-hooks.sh 훅 병합 로직 회귀 테스트 ==="

FIRST_OUT="$TMP/first.out"
MISE_DATA_DIR="$REAL_MISE_DATA_DIR" HOME="$FAKE_HOME" bash "$MERGER" "$PLAYBOOK_DIR" >"$FIRST_OUT" 2>&1

# 실제 설정 파일을 바꾼 첫 실행은 Ansible이 changed 로 보고할 수 있도록 명시적 marker를 내야 한다.
if grep -qF '[CHANGED]' "$FIRST_OUT"; then
  report "첫 훅 병합은 실제 변경 marker 출력" 0
else
  report "첫 훅 병합은 실제 변경 marker 출력" 1 "$(cat "$FIRST_OUT")"
fi

# role 자체도 그 marker를 changed_when에 연결해야 한다. 스크립트가 파일을 바꾸는데
# changed_when:false 로 고정하면 setup/update가 실제 mutation을 changed=0 으로 숨긴다.
AI_ROLE="$REPO_ROOT/ansible/roles/ai_agent/tasks/main.yml"
if grep -qF 'register: ai_agent_hooks_merge_result' "$AI_ROLE" &&
  grep -qE "changed_when:.*\\[CHANGED\\].*ai_agent_hooks_merge_result\.stdout" "$AI_ROLE"; then
  report "Ansible 훅 병합 task가 변경 marker를 changed 상태에 반영" 0
else
  report "Ansible 훅 병합 task가 변경 marker를 changed 상태에 반영" 1
fi

# 1. Gemini: agent-edits-log 훅이 생성되어야 한다.
GEMINI_JSON="$FAKE_HOME/.gemini/config/hooks.json"
if [ -f "$GEMINI_JSON" ] && jq -e '.["agent-edits-log"].PostToolUse[0].hooks[0].command' "$GEMINI_JSON" >/dev/null 2>&1; then
  report "gemini (agent-edits-log 훅 생성)" 0
else
  report "gemini (agent-edits-log 훅 생성)" 1 "$(cat "$GEMINI_JSON" 2>/dev/null || echo '<없음>')"
fi
# Antigravity's Stop entries are direct command handlers, not Claude groups.
if jq -e '([."pre-flight-stop-gate".Stop[].command] |
  (index("ag-user-stop") != null) and
  (any(.[]; contains("agent-stop-adapter.sh") and endswith(" antigravity"))))' "$GEMINI_JSON" >/dev/null; then
  report "Antigravity Stop 등록 및 기존 Stop 명령 보존" 0
else
  report "Antigravity Stop 등록 및 기존 Stop 명령 보존" 1
fi
# Verify the exact installed WSL command launches directly with Bash, without
# PowerShell, Windows profile settings, wsl.exe or a host-side shim.
WSL_STOP_CMD=$(jq -r '[."pre-flight-stop-gate".Stop[].command |
  select(contains("agent-stop-adapter.sh") and endswith(" antigravity"))] | last // empty' "$GEMINI_JSON")
WSL_STOP_OUT=''
WSL_STOP_RC=0
if [ -n "$WSL_STOP_CMD" ]; then
  WSL_STOP_OUT=$(printf '%s\n' '{"fullyIdle":true,"workspacePaths":[],"terminationReason":"model_stop"}' |
    bash -c "$WSL_STOP_CMD") || WSL_STOP_RC=$?
fi
if [ "$WSL_STOP_RC" -eq 0 ] &&
  jq -e '.decision == "continue" and (.reason | contains("workspacePaths"))' <<<"$WSL_STOP_OUT" >/dev/null 2>&1 &&
  ! grep -Eq 'powershell\.exe|wsl\.exe|antigravity-windows-hook' <<<"$WSL_STOP_CMD"; then
  report "Antigravity 등록 명령은 WSL Bash 어댑터를 직접 실행" 0
else
  report "Antigravity 등록 명령은 WSL Bash 어댑터를 직접 실행" 1 "$WSL_STOP_OUT"
fi
if ! grep -Eq 'antigravity-windows-hook|powershell\.exe|wslpath|ai_agent_windows_bridge' "$AI_ROLE"; then
  report "Ansible ai_agent 설치는 Windows 브리지 없이 작동" 0
else
  report "Ansible ai_agent 설치는 Windows 브리지 없이 작동" 1
fi
CODEX_JSON="$FAKE_HOME/.codex/hooks.json"
if jq -e '."user-setting" == "preserve" and
  ([.hooks.Stop[].hooks[].command] |
   (index("codex-user-stop") != null) and
   (any(.[]; contains("agent-stop-adapter.sh") and endswith(" codex"))))' "$CODEX_JSON" >/dev/null; then
  report "Codex Stop 등록 및 기존 설정·Stop 명령 보존" 0
else
  report "Codex Stop 등록 및 기존 설정·Stop 명령 보존" 1
fi

# 2. Gemini: 병합 전 존재하던 무관한 키(unrelated-key)가 보존되어야 한다.
if jq -e '.["unrelated-key"] == "keep-me"' "$GEMINI_JSON" >/dev/null 2>&1; then
  report "gemini (기존 무관 키 보존)" 0
else
  report "gemini (기존 무관 키 보존)" 1 "$(cat "$GEMINI_JSON" 2>/dev/null || echo '<없음>')"
fi

# 3. Claude: PostToolUse에 Edit|Write|MultiEdit|NotebookEdit 매처 훅이 추가되어야 한다.
CLAUDE_JSON="$FAKE_HOME/.claude/settings.json"
# 설치기는 훅을 관리하므로 기존 사용자의 attribution 설정은 건드리지 않는다.
# 특히 빈 문자열로 강제 초기화하면 모든 신규 커밋/PR의 사용자 footer가 소실된다.
if jq -e '.attribution.commit == "user commit footer" and
  .attribution.pr == "user PR footer" and
  .attribution.custom == "leave unchanged"' "$CLAUDE_JSON" >/dev/null; then
  report "claude (기존 사용자 attribution 설정 보존)" 0
else
  report "claude (기존 사용자 attribution 설정 보존)" 1 "$(jq -c '.attribution' "$CLAUDE_JSON")"
fi
if [ -f "$CLAUDE_JSON" ] && jq -e '.hooks.PostToolUse[] | select(.matcher == "Edit|Write|MultiEdit|NotebookEdit")' "$CLAUDE_JSON" >/dev/null 2>&1; then
  report "claude (PostToolUse 매처 훅 추가)" 0
else
  report "claude (PostToolUse 매처 훅 추가)" 1 "$(cat "$CLAUDE_JSON" 2>/dev/null || echo '<없음>')"
fi

# 4. 이전 live 훅만 제거하고 같은 항목의 사용자 훅은 보존한다.
if jq -e '[.hooks.PostToolUse[].hooks[].command] |
  (all(.[]; endswith("pre-flight-live-hook.sh") | not)) and (index("user-hook") != null)' "$CLAUDE_JSON" >/dev/null; then
  report "claude (실시간 검사 제거, 사용자 훅 보존)" 0
else
  report "claude (실시간 검사 제거, 사용자 훅 보존)" 1
fi

# 5. Claude: 완료 선언 직전 게이트 훅(pre-flight-gate-hook.sh)이 Stop에 추가되어야 한다.
if jq -e '.hooks.Stop[] | .hooks[0].command | endswith("pre-flight-gate-hook.sh")' "$CLAUDE_JSON" >/dev/null 2>&1; then
  report "claude (pre-flight-gate-hook 훅 추가)" 0
else
  report "claude (pre-flight-gate-hook 훅 추가)" 1 "$(cat "$CLAUDE_JSON" 2>/dev/null || echo '<없음>')"
fi

# 6. 멱등성: 두 번째 실행 후에도 Claude PostToolUse/Stop 훅이 중복 누적되면 안 된다
#    (PostToolUse: agent-edits-hook.sh + user-hook 2개, Stop: 1개만 유지).
# JSON의 공백·키 순서만 바꿔도 백업과 파일 교체가 발생하면 안 된다.
jq -cS . "$CLAUDE_JSON" >"$TMP/compact.json"
mv "$TMP/compact.json" "$CLAUDE_JSON"
ln "$CLAUDE_JSON" "$TMP/claude-before"
ln "$GEMINI_JSON" "$TMP/gemini-before"
ln "$CODEX_JSON" "$TMP/codex-before"
BACKUPS_BEFORE=$(find "$FAKE_HOME" -name '*.bak.*' | wc -l)
SECOND_OUT="$TMP/second.out"
MISE_DATA_DIR="$REAL_MISE_DATA_DIR" HOME="$FAKE_HOME" bash "$MERGER" "$PLAYBOOK_DIR" >"$SECOND_OUT" 2>&1
if grep -qF '[CHANGED]' "$SECOND_OUT"; then
  report "동일 훅 재실행은 변경 marker 없음" 1 "$(cat "$SECOND_OUT")"
else
  report "동일 훅 재실행은 변경 marker 없음" 0
fi
if [ "$BACKUPS_BEFORE" -eq "$(find "$FAKE_HOME" -name '*.bak.*' | wc -l)" ] &&
  [ "$CLAUDE_JSON" -ef "$TMP/claude-before" ] && [ "$GEMINI_JSON" -ef "$TMP/gemini-before" ]; then
  report "동일 JSON 재실행은 백업·원본 교체 없음" 0
else
  report "동일 JSON 재실행은 백업·원본 교체 없음" 1
fi
if [ "$CODEX_JSON" -ef "$TMP/codex-before" ] &&
  [ "$(jq '[.hooks.Stop[].hooks[].command | select(contains("agent-stop-adapter.sh") and endswith(" codex"))] | length' "$CODEX_JSON")" -eq 1 ]; then
  report "Codex 중복 설치 없음·원본 inode 보존" 0
else
  report "Codex 중복 설치 없음·원본 inode 보존" 1
fi
COUNT=$(jq '.hooks.PostToolUse | length' "$CLAUDE_JSON" 2>/dev/null || echo -1)
STOP_COUNT=$(jq '.hooks.Stop | length' "$CLAUDE_JSON" 2>/dev/null || echo -1)
if [ "$COUNT" -eq 2 ] && [ "$STOP_COUNT" -eq 1 ]; then
  report "claude (재실행해도 훅 중복 누적 없음, 멱등성)" 0
else
  report "claude (재실행해도 훅 중복 누적 없음, 멱등성)" 1 "기대 PostToolUse 2개/Stop 1개 / 실제 ${COUNT}개/${STOP_COUNT}개: $(cat "$CLAUDE_JSON")"
fi

# 관리 훅과 사용자 훅이 같은 그룹이어도 사용자 명령은 남아야 한다.
TMP_JSON="$TMP/mixed.json"
jq '.hooks.PostToolUse[-1].hooks += [{type:"command",command:"mixed-edit"}]
  | .hooks.Stop[-1].hooks += [{type:"command",command:"mixed-stop"}]' "$CLAUDE_JSON" >"$TMP_JSON"
mv "$TMP_JSON" "$CLAUDE_JSON"
cp "$CLAUDE_JSON" "$TMP/claude-changed"
BACKUPS_BEFORE=$(find "$FAKE_HOME" -name '*.bak.*' | wc -l)
MISE_DATA_DIR="$REAL_MISE_DATA_DIR" HOME="$FAKE_HOME" bash "$MERGER" "$PLAYBOOK_DIR"
if [ "$((BACKUPS_BEFORE + 1))" -eq "$(find "$FAKE_HOME" -name '*.bak.*' | wc -l)" ] &&
  [ "$GEMINI_JSON" -ef "$TMP/gemini-before" ]; then
  saved=0
  for backup in "$CLAUDE_JSON".bak.*; do
    if cmp -s "$TMP/claude-changed" "$backup"; then saved=1; fi
  done
  report "달라진 Claude만 백업하고 원본 내용 보존" "$((1 - saved))"
else
  report "달라진 Claude만 백업하고 원본 내용 보존" 1
fi
if jq -e '([.hooks.PostToolUse[].hooks[].command] | index("mixed-edit") != null)
  and ([.hooks.Stop[].hooks[].command] | index("mixed-stop") != null)' "$CLAUDE_JSON" >/dev/null; then
  report "혼합 그룹의 사용자 편집·종료 훅 보존" 0
else
  report "혼합 그룹의 사용자 편집·종료 훅 보존" 1
fi

# Gemini의 관리 그룹 안에서도 사용자 명령과 추가 설정을 보존한다.
jq '."agent-edits-log".PostToolUse[-1].hooks += [{type:"command",command:"gemini-user-hook"}]
  | ."agent-edits-log".custom = "keep"' "$GEMINI_JSON" >"$TMP_JSON"
mv "$TMP_JSON" "$GEMINI_JSON"
MISE_DATA_DIR="$REAL_MISE_DATA_DIR" HOME="$FAKE_HOME" bash "$MERGER" "$PLAYBOOK_DIR"
MISE_DATA_DIR="$REAL_MISE_DATA_DIR" HOME="$FAKE_HOME" bash "$MERGER" "$PLAYBOOK_DIR"
if jq -e '."agent-edits-log" | .custom == "keep" and
  ([.PostToolUse[].hooks[].command] | length == 2 and index("gemini-user-hook") != null)' "$GEMINI_JSON" >/dev/null; then
  report "Gemini 혼합 그룹 보존과 멱등성" 0
else
  report "Gemini 혼합 그룹 보존과 멱등성" 1
fi

# 설정 파일이 외부 dotfiles/설정 저장소를 가리키는 symlink여도 링크 자체를 깨뜨리지
# 않고 referent 내용만 병합해야 한다. mv candidate -> symlink 경로를 그대로 하면 링크가
# 일반 파일로 치환되어 외부 설정 저장소와의 연결이 끊긴다.
SYMLINK_HOME="$TMP/symlink-home"
BACKING="$TMP/settings-backing"
mkdir -p "$SYMLINK_HOME/.claude" "$SYMLINK_HOME/.gemini/config" "$SYMLINK_HOME/.codex" "$BACKING"
echo '{"claude-user":"keep"}' >"$BACKING/claude-settings.json"
echo '{"gemini-user":"keep"}' >"$BACKING/gemini-hooks.json"
echo '{"codex-user":"keep"}' >"$BACKING/codex-hooks.json"
ln -s "$BACKING/claude-settings.json" "$SYMLINK_HOME/.claude/settings.json"
ln -s "$BACKING/gemini-hooks.json" "$SYMLINK_HOME/.gemini/config/hooks.json"
ln -s "$BACKING/codex-hooks.json" "$SYMLINK_HOME/.codex/hooks.json"

MISE_DATA_DIR="$REAL_MISE_DATA_DIR" HOME="$SYMLINK_HOME" bash "$MERGER" "$PLAYBOOK_DIR" >/dev/null

if [ -L "$SYMLINK_HOME/.claude/settings.json" ] &&
  [ -L "$SYMLINK_HOME/.gemini/config/hooks.json" ] &&
  [ -L "$SYMLINK_HOME/.codex/hooks.json" ] &&
  jq -e '."claude-user" == "keep" and (.hooks.PostToolUse | length > 0) and (.hooks.Stop | length > 0)' "$BACKING/claude-settings.json" >/dev/null &&
  jq -e '."gemini-user" == "keep" and (."agent-edits-log".PostToolUse | length > 0) and (."pre-flight-stop-gate".Stop | length > 0)' "$BACKING/gemini-hooks.json" >/dev/null &&
  jq -e '."codex-user" == "keep" and (.hooks.Stop | length > 0)' "$BACKING/codex-hooks.json" >/dev/null; then
  report "symlink-settings (링크 보존 + referent 병합)" 0
else
  report "symlink-settings (링크 보존 + referent 병합)" 1 "claude-link=$(test -L "$SYMLINK_HOME/.claude/settings.json" && echo yes || echo no) gemini-link=$(test -L "$SYMLINK_HOME/.gemini/config/hooks.json" && echo yes || echo no)"
fi

BROKEN_CODEX_HOME="$TMP/broken-codex"
mkdir -p "$BROKEN_CODEX_HOME/.claude" "$BROKEN_CODEX_HOME/.gemini/config" "$BROKEN_CODEX_HOME/.codex"
echo '{"untouched":true}' >"$BROKEN_CODEX_HOME/.claude/settings.json"
echo '{"untouched":true}' >"$BROKEN_CODEX_HOME/.gemini/config/hooks.json"
printf '{not valid' >"$BROKEN_CODEX_HOME/.codex/hooks.json"
code=0
MISE_DATA_DIR="$REAL_MISE_DATA_DIR" HOME="$BROKEN_CODEX_HOME" bash "$MERGER" "$PLAYBOOK_DIR" >/dev/null 2>&1 || code=$?
if [ "$code" -ne 0 ] &&
  [ "$(cat "$BROKEN_CODEX_HOME/.claude/settings.json")" = '{"untouched":true}' ] &&
  [ "$(cat "$BROKEN_CODEX_HOME/.gemini/config/hooks.json")" = '{"untouched":true}' ]; then
  report "broken-codex-hooks (원본 훅 보존, 잘못된 JSON 차단)" 0
else
  report "broken-codex-hooks (원본 훅 보존, 잘못된 JSON 차단)" 1
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

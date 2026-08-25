#!/usr/bin/env bash
# merge-agent-hooks.sh
# 복잡한 JSON 조작 로직을 Ansible 쉘 모듈에서 분리한 단일 목적 스크립트

set -euo pipefail

# lib/ 경로를 리터럴로 분리하여 shellcheck SC1091 오류 회피 (심볼릭 링크 호출 호환성 보장)
MAH_SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
# shellcheck source-path=SCRIPTDIR
source "$MAH_SCRIPT_DIR/../lib/jq-resolve.sh"

PLAYBOOK_DIR="${1:-$HOME/dotfiles/ansible}"
HOOK_SCRIPT="$(readlink -f "$PLAYBOOK_DIR/../bin/hooks/agent-edits-hook.sh" 2>/dev/null || echo "$PLAYBOOK_DIR/../bin/hooks/agent-edits-hook.sh")"

GEMINI_HOOKS="$HOME/.gemini/config/hooks.json"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$GEMINI_HOOKS")" "$(dirname "$CLAUDE_SETTINGS")"
[ -f "$GEMINI_HOOKS" ] || echo '{}' >"$GEMINI_HOOKS"
[ -f "$CLAUDE_SETTINGS" ] || echo '{}' >"$CLAUDE_SETTINGS"

# 아래 네 병합은 예전에 각각 `if [ -n "$JQ" ] && "$JQ" empty "$FILE"; then ... fi` 였고
# else 가 없었다. 그래서 jq 를 해석하지 못하거나 설정 파일이 유효한 JSON 이 아니면
# PostToolUse 실시간 검증 훅과 Stop Pre-Flight 게이트가 통째로 등록되지 않은 채
# 아무 출력 없이 exit 0 으로 끝났다 — ansible 태스크는 성공으로 보고하고, 사용자는
# 이 저장소의 강제 장치 전체가 없는 상태로 "셋업 완료"를 받는다(실측: 깨진
# settings.json 으로 실행 시 rc=0, Stop 게이트 등록 0건).
#
# 훅 등록은 검증이 아니라 "설치"이므로 조용한 생략에 안전한 축이 없다. 실패는 반드시
# 드러내되, 두 설정 파일을 "건드리기 전에" 한꺼번에 검증해 절반만 병합된 어중간한
# 상태로 끝나지 않게 한다.
JQ=$(resolve_jq)
if [ -z "$JQ" ] || ! "$JQ" --version >/dev/null 2>&1; then
  echo "❌ [Hard Block] jq 를 찾을 수 없어 에이전트 훅을 등록하지 못했습니다." >&2
  echo "   미등록 대상: agent-edits-hook(PostToolUse), pre-flight-live-hook(PostToolUse), pre-flight-gate-hook(Stop)" >&2
  echo "   'mise install -y' 로 jq 를 설치한 뒤 다시 실행하십시오." >&2
  exit 1
fi

for _settings in "$GEMINI_HOOKS" "$CLAUDE_SETTINGS"; do
  if ! "$JQ" empty "$_settings" 2>/dev/null; then
    echo "❌ [Hard Block] $_settings 가 유효한 JSON 이 아니어서 에이전트 훅을 등록하지 못했습니다." >&2
    echo "   미등록 대상: agent-edits-hook(PostToolUse), pre-flight-live-hook(PostToolUse), pre-flight-gate-hook(Stop)" >&2
    echo "   해당 파일의 JSON 문법을 고친 뒤 다시 실행하십시오(손상이 심하면 백업 후 '{}' 로 초기화)." >&2
    exit 1
  fi
done
unset _settings

# 1. Gemini
TMP=$(mktemp)
# shellcheck disable=SC2016
"$JQ" --arg cmd "$HOOK_SCRIPT" \
  '. * {
    "agent-edits-log": {
      "PostToolUse": [
        {
          "matcher": "replace_file_content|write_to_file|create_file|write_file|edit_file",
          "hooks": [
            {
              "type": "command",
              "command": $cmd,
              "timeout": 10
            }
          ]
        }
      ]
    }
  }' \
  "$GEMINI_HOOKS" >"$TMP"
mv "$TMP" "$GEMINI_HOOKS"

# 2. Claude
TMP=$(mktemp)
# shellcheck disable=SC2016
"$JQ" --arg cmd "$HOOK_SCRIPT" '
  .attribution.commit = "" | .attribution.pr = ""
  | .hooks.PostToolUse = (
      ((.hooks.PostToolUse // []) | map(select(((.hooks // []) | map(.command) | index($cmd)) == null)))
      + [{matcher: "Edit|Write|MultiEdit|NotebookEdit", hooks: [{type: "command", command: $cmd}]}]
    )
' "$CLAUDE_SETTINGS" >"$TMP"
mv "$TMP" "$CLAUDE_SETTINGS"

# 3. Claude: 실시간 사전 검증 훅(pre-flight-live-hook.sh) 병합
# 편집 직후 그 파일 1개만 pre-flight-check.sh로 즉시 검증해, 커밋 시점 게이트
# (git/.githooks/pre-commit) 이전의 시차를 좁힌다. NotebookEdit은 pre-flight-check가
# 검증하는 대상이 아니라 매처에서 제외한다.
LIVE_HOOK_SCRIPT="$(readlink -f "$PLAYBOOK_DIR/../bin/hooks/pre-flight-live-hook.sh" 2>/dev/null || echo "$PLAYBOOK_DIR/../bin/hooks/pre-flight-live-hook.sh")"

TMP=$(mktemp)
# shellcheck disable=SC2016
"$JQ" --arg cmd "$LIVE_HOOK_SCRIPT" '
  .hooks.PostToolUse = (
      ((.hooks.PostToolUse // []) | map(select(((.hooks // []) | map(.command) | index($cmd)) == null)))
      + [{matcher: "Edit|Write|MultiEdit", hooks: [{type: "command", command: $cmd, timeout: 30}]}]
    )
' "$CLAUDE_SETTINGS" >"$TMP"
mv "$TMP" "$CLAUDE_SETTINGS"

# 4. Claude: 완료 선언 직전 게이트 훅(pre-flight-gate-hook.sh) 병합
# base.AGENTS.md의 Pre-Flight Gate MUST 룰(완료 선언 직전 통합 검증)을 Stop 이벤트에서
# 기계적으로 강제한다. Edit/Write 매처가 아니라 Stop 이벤트라 matcher 없이 등록한다.
GATE_HOOK_SCRIPT="$(readlink -f "$PLAYBOOK_DIR/../bin/hooks/pre-flight-gate-hook.sh" 2>/dev/null || echo "$PLAYBOOK_DIR/../bin/hooks/pre-flight-gate-hook.sh")"

TMP=$(mktemp)
# shellcheck disable=SC2016
"$JQ" --arg cmd "$GATE_HOOK_SCRIPT" '
  .hooks.Stop = (
      ((.hooks.Stop // []) | map(select(((.hooks // []) | map(.command) | index($cmd)) == null)))
      + [{hooks: [{type: "command", command: $cmd, timeout: 60}]}]
    )
' "$CLAUDE_SETTINGS" >"$TMP"
mv "$TMP" "$CLAUDE_SETTINGS"

exit 0

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

# 1. Gemini
GEMINI_HOOKS="$HOME/.gemini/config/hooks.json"
mkdir -p "$(dirname "$GEMINI_HOOKS")"
[ -f "$GEMINI_HOOKS" ] || echo '{}' >"$GEMINI_HOOKS"

JQ=$(resolve_jq)

if [ -n "$JQ" ] && "$JQ" empty "$GEMINI_HOOKS" 2>/dev/null; then
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
fi

# 2. Claude
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
[ -f "$CLAUDE_SETTINGS" ] || echo '{}' >"$CLAUDE_SETTINGS"

if [ -n "$JQ" ] && "$JQ" empty "$CLAUDE_SETTINGS" 2>/dev/null; then
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
fi

exit 0

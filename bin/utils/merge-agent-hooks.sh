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
  echo "   미등록 대상: agent-edits-hook(PostToolUse), pre-flight-gate-hook(Stop)" >&2
  echo "   'mise install -y' 로 jq 를 설치한 뒤 다시 실행하십시오." >&2
  exit 1
fi

for _settings in "$GEMINI_HOOKS" "$CLAUDE_SETTINGS"; do
  if ! "$JQ" empty "$_settings" 2>/dev/null; then
    echo "❌ [Hard Block] $_settings 가 유효한 JSON 이 아니어서 에이전트 훅을 등록하지 못했습니다." >&2
    echo "   미등록 대상: agent-edits-hook(PostToolUse), pre-flight-gate-hook(Stop)" >&2
    echo "   해당 파일의 JSON 문법을 고친 뒤 다시 실행하십시오(손상이 심하면 백업 후 '{}' 로 초기화)." >&2
    exit 1
  fi
done
# 두 파일의 최종 결과를 먼저 만든다. 변환 실패 시 원본은 건드리지 않는다.
GEMINI_TMP=$(mktemp "${GEMINI_HOOKS}.tmp.XXXXXX")
CLAUDE_TMP=""
trap 'rm -f "$GEMINI_TMP" "${CLAUDE_TMP:-}"' EXIT
CLAUDE_TMP=$(mktemp "${CLAUDE_SETTINGS}.tmp.XXXXXX")
# 원본 권한을 유지한 임시 파일을 원자적으로 교체한다.
cp -p "$GEMINI_HOOKS" "$GEMINI_TMP"
cp -p "$CLAUDE_SETTINGS" "$CLAUDE_TMP"

# 파일은 폐기했지만 이전 설치의 등록을 제거하기 위한 경로는 유지한다.
LEGACY_LIVE_NAME="pre-flight-live-hook.sh"
LIVE_HOOK_SCRIPT="$(readlink -f "$PLAYBOOK_DIR/../bin/hooks/$LEGACY_LIVE_NAME" 2>/dev/null || echo "$PLAYBOOK_DIR/../bin/hooks/$LEGACY_LIVE_NAME")"
GATE_HOOK_SCRIPT="$(readlink -f "$PLAYBOOK_DIR/../bin/hooks/pre-flight-gate-hook.sh" 2>/dev/null || echo "$PLAYBOOK_DIR/../bin/hooks/pre-flight-gate-hook.sh")"

# shellcheck disable=SC2016
"$JQ" --arg cmd "$HOOK_SCRIPT" '
  ."agent-edits-log".PostToolUse = (
    ((."agent-edits-log".PostToolUse // []) | map(
      .hooks = ((.hooks // []) | map(select(.command != $cmd)))
      | select(.hooks | length > 0)
    )) + [{
      matcher: "replace_file_content|write_to_file|create_file|write_file|edit_file",
      hooks: [{type: "command", command: $cmd, timeout: 10}]
    }]
  )
' "$GEMINI_HOOKS" >"$GEMINI_TMP"

# Claude의 편집 이력·폐기 훅 제거·Stop 등록을 한 번에 병합한다.
# shellcheck disable=SC2016
"$JQ" --arg cmd "$HOOK_SCRIPT" --arg live "$LIVE_HOOK_SCRIPT" --arg gate "$GATE_HOOK_SCRIPT" '
  .attribution.commit = "" | .attribution.pr = ""
  | .hooks.PostToolUse = (
      ((.hooks.PostToolUse // []) | map(
        .hooks = ((.hooks // []) | map(select(.command != $cmd and .command != $live)))
        | select(.hooks | length > 0)
      ))
      + [{matcher: "Edit|Write|MultiEdit|NotebookEdit", hooks: [{type: "command", command: $cmd}]}]
    )
  | .hooks.Stop = (
      ((.hooks.Stop // []) | map(
        .hooks = ((.hooks // []) | map(select(.command != $gate)))
        | select(.hooks | length > 0)
      ))
      + [{hooks: [{type: "command", command: $gate, timeout: 60}]}]
    )
' "$CLAUDE_SETTINGS" >"$CLAUDE_TMP"

replace_if_changed() {
  local original=$1 candidate=$2 backup
  # 들여쓰기·키 순서만 다른 경우에도 원본과 수정 시각을 유지한다.
  if "$JQ" -e -s '.[0] == .[1]' "$original" "$candidate" >/dev/null; then
    return 0
  fi
  backup=$(mktemp "${original}.bak.XXXXXX")
  cp -p "$original" "$backup"
  mv "$candidate" "$original"
}

replace_if_changed "$GEMINI_HOOKS" "$GEMINI_TMP"
replace_if_changed "$CLAUDE_SETTINGS" "$CLAUDE_TMP"

#!/usr/bin/env bash
# pre-flight-live-hook.sh - AI가 파일을 수정한 직후(PostToolUse) 그 파일 1개만 대상으로
# pre-flight-check.sh를 즉시 실행하는 실시간 검증 훅.
#
# 배경: bin/hooks/pre-flight-check.sh는 이미 git/.githooks/pre-commit에서 커밋 시점마다
# 실행되는 진짜 하드 게이트다(실패 시 커밋 자체가 막힘). 하지만 "에이전트가 코드를
# 고치고 완료를 선언하는 시점"과 "실제로 커밋되는 시점" 사이에는 여전히
# base.AGENTS.md의 MUST 문구(에이전트의 자율적 판단)에만 의존하는 시차가 있었다.
# 이 훅은 그 시차를 없애 편집 직후 바로 피드백을 주는 2차 방어선이고, 최종 판정은
# 여전히 pre-commit 훅이 맡는다(그래서 이 훅은 실패해도 에이전트 루프를 막지 않는
# fail-open 정책을 따른다 — agent-edits-hook.sh와 동일한 이유).
#
# 스코프 제외: .tf/.tfvars/.bicep는 validate_terraform/validate_bicep이 init 등
# 네트워크·빌드 의존 단계를 거쳐 편집 1회마다 돌리면 지연이 크다. 이 확장자는
# 지금처럼 커밋 시점 게이트에서만 검증되고, 여기서는 건너뛴다.
#
# 저장소 대상 판정(~/workspace 하위 또는 dotfiles 자신, 또는 루트에 옵트인
# pre-flight-check.sh)은 git/.githooks/pre-commit의 PFC_TARGET 로직과 의도적으로
# 동일하게 맞췄다. 두 훅은 실행 컨텍스트가 달라(git 훅 vs Claude Code 훅) 공용
# 라이브러리로 뽑으면 검증된 커밋 게이트까지 건드리는 리스크가 있어 최소 로직만
# 중복 유지한다(git-relpath.sh 상단 주석과 동일한 판단).
#
# 성공 시에도 완전 무음이면 "통과했다"와 "훅이 애초에 안 돌았다"가 구분이 안 된다.
# 그래서 pre-flight-check.sh를 run-suite.sh에 태워 압축된 "-> [✓] <경로>" 한 줄을
# decision:block 없이(=차단·재응답 유발 없이) additionalContext로만 조용히 실어
# 보낸다. 대화 메시지로는 안 보이고 에이전트 컨텍스트에만 쌓이는 채널이라 실측상
# 몇 줄 수준이면 비용이 감내할 만하다(run-suite.sh 채택 경위는
# bin/hooks/pre-flight-gate-hook.sh 헤더 참조 — 실패 시 압축 없이 원본을 그대로
# 보여주는 동작은 여기서도 동일하게 유지).
set -uo pipefail

PFL_SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
# shellcheck source-path=SCRIPTDIR
source "$PFL_SCRIPT_DIR/../lib/git-relpath.sh"
# shellcheck source-path=SCRIPTDIR
source "$PFL_SCRIPT_DIR/../lib/jq-resolve.sh"

JQ=$(resolve_jq)
{ [ -n "$JQ" ] && "$JQ" --version >/dev/null 2>&1; } || exit 0

payload=$(cat)

# Claude Code(tool_input.file_path) / Antigravity(toolCall.args.TargetFile) 스키마 모두 지원
target=$(
  "$JQ" -r '
    (.toolCall.args.TargetFile // .tool_input.file_path // "")
    | tostring | gsub("[\t\r\n]"; " ")
  ' <<<"$payload" 2>/dev/null
) || exit 0

[ -n "${target:-}" ] || exit 0
[ -e "$target" ] || exit 0

# 네트워크/빌드 의존 확장자는 실시간 훅에서 제외 (커밋 게이트에서만 검증됨)
case "$target" in
*.tf | *.tfvars | *.bicep) exit 0 ;;
esac

IFS=$'\t' read -r target git_root < <(resolve_target_and_git_root "$target")
[ -n "$git_root" ] || exit 0

pfc="$git_root/bin/hooks/pre-flight-check.sh"
rs="$git_root/bin/hooks/run-suite.sh"
if [[ "$git_root/" == "$HOME/workspace/"* ]] || [ "$(basename "$git_root")" = "dotfiles" ]; then
  [ -x "$pfc" ] || pfc="$HOME/dotfiles/bin/hooks/pre-flight-check.sh"
  [ -x "$rs" ] || rs="$HOME/dotfiles/bin/hooks/run-suite.sh"
elif [ -x "$git_root/pre-flight-check.sh" ]; then
  pfc="$git_root/pre-flight-check.sh"
  rs="$HOME/dotfiles/bin/hooks/run-suite.sh"
else
  exit 0
fi
[ -x "$pfc" ] || exit 0
[ -x "$rs" ] || exit 0

# --pfc-args="$target"는 SCRIPTS 중 경로에 pre-flight-check.sh가 포함된 항목에만
# run-suite.sh가 패스스루한다(explicit 모드로 이 파일 1개만 검증하게 됨).
out=$(env -C "$git_root" "$rs" "$pfc" --pfc-args="$target" 2>&1)
rc=$?

if [ "$rc" -eq 0 ]; then
  # 통과: decision 없이 additionalContext만 조용히 실어 보낸다(차단·재응답 없음).
  # shellcheck disable=SC2016
  "$JQ" -n --arg ctx "$out" '
    { hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: $ctx } }
  ' 2>/dev/null
  exit 0
fi

# 실패: exit 0 + JSON decision:block으로만 에이전트에게 피드백이 전달된다
# (exit 2는 stdout의 JSON을 무시하고 stderr만 넘기므로 여기선 쓰지 않는다).
# shellcheck disable=SC2016
"$JQ" -n --arg reason "pre-flight-check 실패: $(basename "$target")" --arg ctx "$out" '
  {
    decision: "block",
    reason: $reason,
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $ctx
    }
  }
' 2>/dev/null
exit 0

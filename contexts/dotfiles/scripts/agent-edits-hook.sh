#!/usr/bin/env bash
# agent-edits-hook.sh - AI 편집 이력을 프로젝트 루트 .agent-state/edits.log에 1줄 append하는 PostToolUse 훅.
#
# Claude Code와 Antigravity IDE는 같은 이벤트명(PostToolUse)을 쓰지만 페이로드 스키마가 다르다.
# (2026-07-26 실측: Antigravity는 toolCall.name / toolCall.args.TargetFile / workspacePaths[0],
#  Claude Code는 tool_name / tool_input.file_path / cwd)
# 도구명 화이트리스트 대신 "편집 대상 경로 필드의 존재 여부"로 판별하므로, 아직 관측되지 않은
# 파일 생성 계열 도구도 자동으로 포함되고 조회 계열(view_file의 AbsolutePath)은 자연히 제외된다.
#
# 기록 포맷: <ISO8601> | <파일경로> | <출처> | <작업 목적> | <결과>
# 훅은 기계적 사실만 남기고(출처=hook:<도구명>, 목적=-), 참조 룰 문서와 작업 목적은
# 에이전트가 agent: 출처로 별도 1줄을 추가한다(base.AGENTS.md 9장).
set -uo pipefail

# 훅 실패가 에이전트 루프를 막아서는 안 되므로, 어떤 경로로 빠져나가든 정상 종료한다.
#
# jq 해석 주의: PATH의 jq는 mise shim일 수 있고, shim은 mise 설정이 없는 디렉토리(대부분의
# 사용자 프로젝트)에서 "No version is set" 오류로 실패한다(2026-07-26 실측: /tmp 임시 저장소
# e2e에서 훅이 조용히 no-op 됨). command -v 존재 확인만으로는 부족하므로 실제 실행을 검증하고,
# 실패 시 mise 설치 원본 바이너리로 폴백한다. pre-flight-check.sh의 has_tool()과 같은 계열 문제.
JQ=$(command -v jq 2>/dev/null) || JQ=""
if [ -z "$JQ" ] || ! "$JQ" --version >/dev/null 2>&1; then
  # mise는 jq를 installs/jq/<버전>/jq 단일 파일로 설치한다(bin/ 하위 아님). 버전 별칭
  # 심볼릭 링크(latest 등)를 제외하기 위해 실파일만 찾아 최신 버전을 고른다.
  JQ=$(find "$HOME/.local/share/mise/installs/jq" -maxdepth 3 -name jq -type f 2>/dev/null | sort -V | tail -1)
  { [ -n "$JQ" ] && "$JQ" --version >/dev/null 2>&1; } || exit 0
fi

payload=$(cat)

fields=$(
  "$JQ" -r '
    def clean: tostring | gsub("[\t\r\n|]"; " ") | sub("^ +"; "") | sub(" +$"; "");
    [
      ((.toolCall.name // .tool_name // "") | clean),
      ((.toolCall.args.TargetFile // .tool_input.file_path // "") | clean),
      ((.workspacePaths[0]? // .cwd // "") | clean),
      (((.error // (.tool_response | objects | .error) // "") | clean))
    ] | @tsv
  ' <<<"$payload" 2>/dev/null
) || exit 0

IFS=$'\t' read -r tool target root err <<<"$fields"

# 편집 대상이 없는 호출(조회 도구, toolCall이 null인 스텝)은 기록 대상이 아니다.
[ -n "${target:-}" ] || exit 0

# 에이전트가 로그 파일 자체를 편집 도구로 갱신하면 그 편집을 훅이 재기록하는 자기 오염이
# 발생한다(2026-07-26 실측: Antigravity가 agent 라인을 replace_file_content로 추가). 제외한다.
# 파일명(edits.log)만 비교하면 무관한 프로젝트 파일까지 침묵시키므로 .agent-state/ 경로까지 본다.
case "$target" in */.agent-state/edits.log) exit 0 ;; esac

# 로그를 둘 프로젝트 루트 결정: git 최상위 > 페이로드의 워크스페이스 > 대상 파일의 디렉토리.
# git 최상위를 우선하는 이유: 사용자가 모노레포의 하위 디렉토리를 워크스페이스로 열면
# workspacePaths가 저장소 루트와 달라져 같은 저장소의 이력이 여러 파일로 쪼개진다.
# 저장소당 로그 1개여야 flywheel이 git 이력(git log -S)과 대조할 수 있다.
# 심볼릭 링크로 접근한 프로젝트는 git이 실경로를 반환하는 반면 대상 경로는 링크 경로로 남아
# 접두사 제거가 실패하고 절대 경로가 기록된다(2026-07-26 실측). 양쪽을 실경로로 통일한다.
target=$(readlink -f "$target" 2>/dev/null || echo "$target")
target_dir=$(dirname "$target")
git_root=$(git -C "$target_dir" rev-parse --show-toplevel 2>/dev/null) || git_root=""
if [ -n "$git_root" ]; then
  root="$git_root"
elif [ -z "${root:-}" ] || [ ! -d "$root" ]; then
  root="$target_dir"
fi
[ -d "$root" ] || exit 0

# 파일 경로만 남기고 내용은 절대 기록하지 않는다(base.AGENTS.md 7장 민감 데이터 마스킹).
rel="${target#"$root"/}"
[ -n "${err:-}" ] && result="ERROR:$err" || result="OK"

# 2>/dev/null을 리다이렉션보다 앞에 두어야 한다. 뒤에 두면 append 실패(읽기 전용 프로젝트 등)
# 시점에 이미 stderr가 살아 있어 "Permission denied"가 에이전트 출력에 섞인다(2026-07-26 실측).
# 로그는 프로젝트 루트가 아니라 .agent-state/ 하위에 모은다. 디렉토리가 없으면 append가 통째로
# 실패하므로 먼저 확보하되, 실패해도 훅이 에이전트 작업을 막지 않도록 무시한다.
mkdir -p "$root/.agent-state" 2>/dev/null || true
printf '%s | %s | hook:%s | - | %s\n' \
  "$(date -Iseconds 2>/dev/null || date)" "$rel" "${tool:-unknown}" "$result" \
  2>/dev/null >>"$root/.agent-state/edits.log"

# 로그 상한. 이 훅은 편집마다 1줄씩 append 하기만 해서 파일이 무한히 자란다. 소비처인
# prompt-flywheel.sh 는 tail -20 만 보고, 그보다 오래된 편집 근거는 git 이력으로 확인하는
# 편이 정확하므로 최근 것만 남기면 충분하다. 훅이 에이전트 루프를 막아서는 안 되므로
# 어떤 실패도 무시한다(로테이션 실패는 다음 편집에서 다시 시도된다).
EDITS_LOG="$root/.agent-state/edits.log"
if [ "$(wc -l <"$EDITS_LOG" 2>/dev/null || echo 0)" -gt 5000 ]; then
  { tail -n 2500 "$EDITS_LOG" >"$EDITS_LOG.tmp" && mv "$EDITS_LOG.tmp" "$EDITS_LOG"; } 2>/dev/null || true
  rm -f "$EDITS_LOG.tmp" 2>/dev/null || true
fi

exit 0

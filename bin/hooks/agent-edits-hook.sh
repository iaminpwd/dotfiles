#!/usr/bin/env bash
# agent-edits-hook.sh - AI 편집 이력을 프로젝트 루트 .agent-state/edits.log에 1줄 append하는 PostToolUse 훅.
#
# Claude Code / Antigravity IDE 페이로드 스키마 차이 대응
# 편집 대상 경로 필드의 존재 여부로 편집 도구(수정/생성)와 조회 도구를 자동 구분
#
# agent-edits-hook.sh: AI 편집 이력을 .agent-state/edits.log에 기록
# 포맷: <ISO8601> | <파일경로> | <출처> | <작업 목적> | <결과>
# -e(errexit) 는 의도적으로 제외: 훅 실패가 에이전트 루프를 멈추지 않도록 보장.
# 개별 오류 지점은 아래에서 각각 `|| exit 0` 으로 명시적 처리.
set -uo pipefail

# lib/ 경로를 리터럴로 분리하여 shellcheck SC1091 오류 회피 (심볼릭 링크 호출 호환성 보장)
AEH_SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
# shellcheck source-path=SCRIPTDIR
source "$AEH_SCRIPT_DIR/../lib/git-relpath.sh"
# shellcheck source-path=SCRIPTDIR
source "$AEH_SCRIPT_DIR/../lib/jq-resolve.sh"

# 훅 실패가 에이전트 루프를 저해하지 않도록 보장
JQ=$(resolve_jq)
{ [ -n "$JQ" ] && "$JQ" --version >/dev/null 2>&1; } || exit 0

payload=$(cat)

# 구분자로 탭(@tsv)을 쓰지 않는다. 탭은 IFS 공백문자라 `IFS=$'\t' read` 가 연속 탭을
# 구분자 하나로 합쳐 빈 필드를 삼킨다. 여기서는 네 필드 중 가운데 둘이 정상적으로 빌 수
# 있어(cwd/workspacePaths 가 없는 페이로드, 에러 없는 성공 호출) 그 순간 필드가 밀린다.
#   실측 1: cwd 없이 tool_response.error 가 있는 페이로드 -> err 이 root 자리로 밀리고
#           err 이 비어 결과가 ERROR:... 가 아니라 OK 로 기록됐다. 감사 로그가 실패한
#           편집을 성공으로 남긴다.
#   실측 2: tool_name 없이 file_path 만 있는 페이로드 -> 경로가 tool 자리로 밀리고
#           root 판정까지 어긋나, 저장소 밖(부모 디렉토리)의 .agent-state 에
#           "| <디렉토리명> | hook:<전체경로> |" 라는 깨진 줄이 기록됐다.
# 아래 root 폴백 사슬(git_root > 워크스페이스 > 파일 디렉토리) 자체가 "root 가 빌 수 있다"를
# 전제로 짜여 있으므로, 그 경로에서 파싱이 깨지는 것은 설계와 어긋난다.
# unit separator(\037)는 IFS 공백이 아니라 연속해도 합쳐지지 않는다. clean 이 그 문자까지
# 값에서 제거하므로 구분자가 값과 충돌하지도 않는다.
# (validate-alert-rules.sh 헤더가 같은 @tsv 함정을 짚고 있다 — 그쪽은 필드 안의 개행,
#  여기는 빈 필드로 발현만 다르고 원인은 같다.)
fields=$(
  "$JQ" -r '
    def clean: tostring | gsub("[\t\r\n|\u001f]"; " ") | sub("^ +"; "") | sub(" +$"; "");
    [
      ((.toolCall.name // .tool_name // "") | clean),
      ((.toolCall.args.TargetFile // .tool_input.file_path // "") | clean),
      ((.workspacePaths[0]? // .cwd // "") | clean),
      (((.error // (.tool_response | objects | .error) // "") | clean))
    ] | join("\u001f")
  ' <<<"$payload" 2>/dev/null
) || exit 0

IFS=$'\037' read -r tool target root err <<<"$fields"

# 편집 대상이 없는 호출(조회 도구, toolCall이 null인 스텝)은 기록 대상이 아니다.
[ -n "${target:-}" ] || exit 0

# 로그 자기 오염(에이전트가 로그 갱신 시 훅이 재기록) 방지를 위해 edits.log 경로 제외
case "$target" in */.agent-state/edits.log) exit 0 ;; esac

# 로그 디렉토리 결정: git 최상위 > 워크스페이스 > 파일 디렉토리
# 모노레포 환경 통합 기록 및 심볼릭 링크 경로 불일치 방지를 위해 실경로(realpath) 사용
IFS=$'\t' read -r target git_root < <(resolve_target_and_git_root "$target")
target_dir=$(dirname "$target")
if [ -n "$git_root" ]; then
  root="$git_root"
elif [ -z "${root:-}" ] || [ ! -d "$root" ]; then
  root="$target_dir"
fi
[ -d "$root" ] || exit 0
root=$(readlink -f "$root" 2>/dev/null || echo "$root")

# root가 target을 실제로 포함하지 않으면(무관한 워크스페이스 cwd로 오귀속되는 경우,
# 예: 다른 도구가 프로젝트 밖 경로를 편집했는데 워크스페이스가 열려 있는 경우)
# 상대경로 변환이 깨져 절대경로가 그대로 새어나가므로, 파일 자체 디렉터리로 재라우팅한다.
case "$target" in
"$root" | "$root"/*) : ;;
*) root="$target_dir" ;;
esac

# 파일 경로만 남기고 내용은 절대 기록하지 않는다(base.AGENTS.md 7장 민감 데이터 마스킹).
if [ "$target" = "$root" ]; then
  rel="$(basename "$target")"
else
  rel="${target#"$root"/}"
fi
[ -n "${err:-}" ] && result="ERROR:$err" || result="OK"

# 로그 작성 실패 시 조용히 무시 (stderr 리다이렉션 순서 주의하여 에이전트 출력 오염 방지)
mkdir -p "$root/.agent-state" 2>/dev/null || true
# idempotency:bypass (로그 파일 연속 기록이므로 상태 검증 불필요)
printf '%s | %s | hook:%s | - | %s\n' \
  "$(date -Iseconds 2>/dev/null || date)" "$rel" "${tool:-unknown}" "$result" \
  2>/dev/null >>"$root/.agent-state/edits.log"

# 무한 증식 방지 로그 로테이션 (실패 시 무시)
EDITS_LOG="$root/.agent-state/edits.log"
if [ "$(wc -l <"$EDITS_LOG" 2>/dev/null || echo 0)" -gt 5000 ]; then
  { tail -n 2500 "$EDITS_LOG" >"$EDITS_LOG.tmp" && mv "$EDITS_LOG.tmp" "$EDITS_LOG"; } 2>/dev/null || true
  rm -f "$EDITS_LOG.tmp" 2>/dev/null || true
fi

exit 0

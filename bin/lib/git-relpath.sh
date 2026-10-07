#!/usr/bin/env bash
# git-relpath.sh - 파일 경로를 실경로(realpath)로 정규화하고 소속 git 저장소 루트를
# 조회하는 공용 라이브러리 (SSOT).
# agent-edits-hook.sh(자동 PostToolUse 훅)와 record-provenance.sh(수동 CLI)가 .agent-state/edits.log에
# 같은 REL 규칙으로 기록해야 하는데, 이 realpath+git-root 조회 로직이 두 스크립트에
# 그대로 중복돼 있던 부분만 뽑아냈다. 각 스크립트 고유의 폴백/컨테인먼트 판정 로직은
# 서로 의도적으로 달라(훅은 workspacePaths 폴백까지 있고 CLI는 없음) 건드리지 않는다.
#
# [주의] source 전용 라이브러리이므로 호출자의 셸 옵션을 보존하기 위해 set -euo pipefail을 선언하지 않습니다.
#
# 사용법:
#   source "$LIB_PATH/git-relpath.sh"
#   IFS=$'\t' read -r resolved git_root < <(resolve_target_and_git_root "$path")

# GNU readlink -f는 macOS 기본 BSD readlink에 없다. 이 라이브러리의 핵심 계약이
# 실경로 정규화이므로 옵션 미지원 시 input 그대로로 폴백하면 성공처럼 보이면서 소비자의
# 컨테인먼트/REL 계산 기준만 갈라진다. plain readlink + cd -P로 final symlink와 부모
# 디렉터리 symlink를 모두 해석한다.
git_relpath_canonical_path() {
  local path=$1 dir target
  while [ -L "$path" ]; do
    dir=$(cd -P "$(dirname "$path")" 2>/dev/null && pwd) || return 1
    target=$(readlink "$path" 2>/dev/null) || return 1
    case "$target" in
    /*) path="$target" ;;
    *) path="$dir/$target" ;;
    esac
  done
  dir=$(cd -P "$(dirname "$path")" 2>/dev/null && pwd) || return 1
  printf '%s/%s\n' "$dir" "$(basename "$path")"
}

# resolve_target_and_git_root <path>
# stdout: "<정규화된 실경로>\t<git 저장소 루트 또는 빈 문자열>"
resolve_target_and_git_root() {
  local input="$1" resolved dir root
  resolved=$(git_relpath_canonical_path "$input" 2>/dev/null || printf '%s\n' "$input")
  dir=$(dirname "$resolved")
  root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || root=""
  printf '%s\t%s\n' "$resolved" "$root"
}

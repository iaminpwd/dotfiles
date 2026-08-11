#!/usr/bin/env bash
# prune-orphan-skills.sh
# ai_agent 롤이 관리하는 글로벌 스킬 레지스트리(~/.claude/skills, ~/.gemini/config/skills)에서
# contexts/ 도메인 목록에 더 이상 없는 "고아" 폴더를 정리한다.
#
# ~/.claude/skills 등은 이 저장소 전용이 아니라 Claude Code/Gemini의 범용 글로벌 스킬
# 레지스트리다. 사용자가 직접 만들었거나 다른 도구로 설치한 스킬이 같이 있을 수 있는데,
# 이름이 우연히 contexts/ 도메인 목록에 없다고 무조건 지우면 그 사용자 데이터가 확인
# 없이 사라진다(실측: ~/.config 폴딩 사고와 같은 클래스 — 공유 경로를 우리가 전부
# 소유한다고 오판). 그래서 폴더 내부가 "전부 심볼릭 링크(=이 롤이 만든 것)"일 때만
# 지우고, 실제 파일이 하나라도 섞여 있으면 우리 것이 아니라고 보고 건드리지 않는다.
#
# 사용: prune-orphan-skills.sh <skills_dir> <유효 도메인 이름...>

set -euo pipefail

SKILLS_DIR="$1"
shift
VALID_DOMAINS=("$@")

[ -d "$SKILLS_DIR" ] || exit 0

_is_valid_domain() {
  local name=$1 d
  for d in "${VALID_DOMAINS[@]}"; do
    [ "$d" = "$name" ] && return 0
  done
  return 1
}

for dir in "$SKILLS_DIR"/*/; do
  [ -d "$dir" ] || continue
  name=$(basename "$dir")
  _is_valid_domain "$name" && continue

  FOREIGN=0
  while IFS= read -r -d '' entry; do
    if [ ! -L "$entry" ]; then
      FOREIGN=1
      break
    fi
  done < <(find "$dir" -mindepth 1 -print0)

  if [ "$FOREIGN" -eq 0 ]; then
    rm -rf "$dir"
    echo "  [PRUNED] $dir (contexts/에서 사라진 도메인 — 전부 심볼릭 링크라 안전하게 정리)"
  else
    echo "  [SKIP] $dir 는 contexts/ 도메인 목록에 없지만 실제 파일이 섞여 있어 건드리지 않음 (수동 확인 필요)" >&2
  fi
done
exit 0

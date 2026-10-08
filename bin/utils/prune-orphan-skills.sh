#!/usr/bin/env bash
# prune-orphan-skills.sh
# ai_agent 롤이 관리하는 글로벌 스킬 레지스트리(~/.claude/skills, ~/.gemini/config/skills)에서
# contexts/ 도메인 목록에 더 이상 없는 "고아" 폴더를 정리한다.
#
# ~/.claude/skills 등은 이 저장소 전용이 아니라 Claude Code/Gemini의 범용 글로벌 스킬
# 레지스트리다. 사용자가 직접 만들었거나 다른 도구로 설치한 스킬이 같이 있을 수 있는데,
# 이름이 우연히 contexts/ 도메인 목록에 없다고 무조건 지우면 그 사용자 데이터가 확인
# 없이 사라진다(실측: ~/.config 폴딩 사고와 같은 클래스 — 공유 경로를 우리가 전부
# 소유한다고 오판).
#
# 단순히 "전부 심볼릭 링크"인지만 봐도 부족하다. 사용자가 자신의 스킬 저장소를
# SKILL.md/references symlink로 등록하거나, 이 저장소의 스킬을 다른 이름의 alias로
# 등록할 수도 있기 때문이다. 이 롤이 만드는 경로는 항상
#   skills/<domain>/<asset> -> contexts/<same-domain>/<asset>
# 이므로 폴더 이름과 source domain까지 일치할 때만 dotfiles 소유로 판정한다.
#
# 사용: prune-orphan-skills.sh <skills_dir> <유효 도메인 이름...>

set -euo pipefail

SKILLS_DIR="$1"
shift
VALID_DOMAINS=("$@")

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
MANAGED_CONTEXTS_DIR=$(cd "$SCRIPT_DIR/../../contexts" && pwd -P)

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
  # A live skill domain can lose an individual optional asset. Ansible only
  # links assets that currently exist and otherwise leaves old links behind.
  # Prune only a broken symlink at this role's exact managed source path:
  # never remove user files, foreign symlinks, or working managed links.
  if _is_valid_domain "$name"; then
    for asset in SKILL.md references scripts examples; do
      entry="${dir}${asset}"
      managed_source="$MANAGED_CONTEXTS_DIR/$name/$asset"
      if [ -L "$entry" ] && [ "$(readlink "$entry")" = "$managed_source" ] &&
        [ ! -e "$managed_source" ]; then
        rm "$entry"
        echo "  [PRUNED] $entry (removed managed asset: $managed_source)"
      fi
    done
    continue
  fi

  FOREIGN=0
  while IFS= read -r -d '' entry; do
    if [ ! -L "$entry" ]; then
      FOREIGN=1
      break
    fi

    link_target=$(readlink "$entry")
    case "$link_target" in
    "$MANAGED_CONTEXTS_DIR/$name"/*)
      # ai_agent 롤이 생성하는 링크는 같은 이름의 contexts/<domain>/ 아래 정규화된
      # 절대 src를 그대로 사용한다. ../ 같은 우회 경로를 소유 링크로 오판하지 않는다.
      case "$link_target" in
      *"/../"* | *"/./")
        FOREIGN=1
        break
        ;;
      esac
      ;;
    *)
      FOREIGN=1
      break
      ;;
    esac
  done < <(find "$dir" -mindepth 1 -print0)

  if [ "$FOREIGN" -eq 0 ]; then
    rm -rf "$dir"
    echo "  [PRUNED] $dir (contexts/에서 사라진 도메인 — 모든 링크가 이 저장소 contexts/ 소유라 안전하게 정리)"
  else
    echo "  [SKIP] $dir 는 contexts/ 도메인 목록에 없지만 외부 소유 파일/링크가 있어 건드리지 않음 (수동 확인 필요)" >&2
  fi
done
exit 0

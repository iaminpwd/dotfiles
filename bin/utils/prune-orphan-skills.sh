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

# The registry is shared. A directory is ours only if it contains at least one
# exact historical asset symlink and every entry matches the old role's layout.
# Capture find's exit status: a failed scan must never authorize rm -rf.
SCAN_FILE=$(mktemp)
trap 'rm -f "$SCAN_FILE"' EXIT

for dir in "$SKILLS_DIR"/*/; do
  dir=${dir%/}
  [ -d "$dir" ] || continue
  # A linked skill directory may point to an external registry. Never traverse it.
  if [ -L "$dir" ]; then
    echo "  [SKIP] $dir 는 사용자 소유 심볼릭 링크 디렉토리로 보존" >&2
    continue
  fi
  name=${dir##*/}
  # A live skill domain can lose an individual optional asset. Ansible only
  # links assets that currently exist and otherwise leaves old links behind.
  # Prune only a broken symlink at this role's exact managed source path:
  # never remove user files, foreign symlinks, or working managed links.
  if _is_valid_domain "$name"; then
    for asset in SKILL.md references scripts examples; do
      entry="$dir/$asset"
      managed_source="$MANAGED_CONTEXTS_DIR/$name/$asset"
      if [ -L "$entry" ] && [ "$(readlink "$entry")" = "$managed_source" ] &&
        [ ! -e "$managed_source" ]; then
        rm "$entry"
        echo "  [PRUNED] $entry (removed managed asset: $managed_source)"
      fi
    done
    continue
  fi

  if ! find "$dir" -mindepth 1 -print0 >"$SCAN_FILE"; then
    echo "  [SKIP] $dir 항목 조회 실패 — 소유권을 검증할 수 없어 삭제하지 않음" >&2
    continue
  fi

  FOREIGN=0
  OWNED=0
  while IFS= read -r -d '' entry; do
    if [ ! -L "$entry" ]; then
      FOREIGN=1
      break
    fi
    # The old role linked only these four named assets to exact absolute paths.
    # An arbitrary custom symlink beneath contexts/<same-name>/ is user-owned.
    asset=${entry##*/}
    case "$asset" in
    SKILL.md | references | scripts | examples) ;;
    *)
      FOREIGN=1
      break
      ;;
    esac
    if [ "$(readlink "$entry")" != "$MANAGED_CONTEXTS_DIR/$name/$asset" ]; then
      FOREIGN=1
      break
    fi
    OWNED=1
  done <"$SCAN_FILE"

  if [ "$FOREIGN" -eq 0 ] && [ "$OWNED" -eq 1 ]; then
    rm -rf "$dir"
    echo "  [PRUNED] $dir (삭제된 contexts/ 도메인의 관리 에셋 링크만 존재)"
  else
    echo "  [SKIP] $dir 는 관리 링크만 있는 폴더로 확인되지 않아 보존 (수동 확인 필요)" >&2
  fi
done
exit 0

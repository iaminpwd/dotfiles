#!/usr/bin/env bash
# safe-link-backup.sh
# ansible.builtin.file(state: link, force: true)로 심볼릭 링크를 강제 생성하기 전,
# 목적지의 실제 파일과, 관리 원본이 아닌 사용자 심볼릭 링크를 백업한다.
#
# force: true는 사용자 파일과 외부 심볼릭 링크를 모두 교체할 수 있다.
# 기본(target-only) 모드는 레거시 호출과 호환되도록 실제 파일/디렉토리만 백업한다.
# Ansible의 force:true 링크 설치 경로는 반드시 --link-pairs <source> <target>을
# 사용한다. 설치할 원본과 정확히 같은 링크만 보존하고, 다른 링크(깨진 링크 포함)는
# 기존 사용자 설정을 복원할 수 있도록 이름을 바꿔 백업한다.
#
# 백업 이름은 초 단위 timestamp를 기본으로 쓰되 같은 초에 같은 경로를 다시 백업하면
# 기존 백업을 덮어쓰지 않도록 .1, .2 ... suffix로 다음 빈 이름을 찾는다.
#
# 사용: safe-link-backup.sh [target ...] (레거시)
#       safe-link-backup.sh --link-pairs <source> <target> [...] (Ansible 링크 설치 전)

set -euo pipefail

_next_backup_path() {
  local target=$1 timestamp=$2 candidate suffix=0
  candidate="$target.backup.$timestamp"

  while [ -e "$candidate" ] || [ -L "$candidate" ]; do
    suffix=$((suffix + 1))
    candidate="$target.backup.$timestamp.$suffix"
  done

  printf '%s\n' "$candidate"
}

_backup_target() {
  local target=$1 timestamp backup
  timestamp=$(date +%F-%H%M%S)
  backup=$(_next_backup_path "$target" "$timestamp")
  mv "$target" "$backup"
  echo "  [BACKUP] $target -> $backup (기존 사용자 파일 또는 링크 보존)"
}

if [ "${1:-}" = "--link-pairs" ]; then
  shift
  if [ "$(($# % 2))" -ne 0 ]; then
    echo "usage: $0 --link-pairs <source> <target> [<source> <target> ...]" >&2
    exit 2
  fi
  while [ "$#" -gt 0 ]; do
    SOURCE=$1
    TARGET=$2
    shift 2
    if [ -L "$TARGET" ]; then
      # Ansible creates an absolute link with precisely this src. A different
      # link is not ours: back it up before force:true replaces the path.
      [ "$(readlink "$TARGET")" = "$SOURCE" ] && continue
      _backup_target "$TARGET"
    elif [ -e "$TARGET" ]; then
      _backup_target "$TARGET"
    fi
  done
else
  # Legacy target-only contract: no source is provided, so symlink ownership
  # cannot be established. Preserve existing caller semantics.
  for TARGET in "$@"; do
    if [ -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
      _backup_target "$TARGET"
    fi
  done
fi
exit 0

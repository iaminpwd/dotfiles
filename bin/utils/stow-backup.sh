#!/usr/bin/env bash
# stow-backup.sh
# stow 충돌 방지를 위한 백업 유틸리티

set -euo pipefail

PKG="$1"
DOTFILES_DIR="$2"
HOME_DIR="$3"
BACKUP_TIMESTAMP=$(date +%F-%H%M%S)

_canonicalize() {
  readlink -f "$1" 2>/dev/null || realpath "$1" 2>/dev/null || echo "$1"
}

# TARGET이 이미 심볼릭 링크인데 stow 소유 형식이 아니면 백업으로 치운다. 절대경로
# 심볼릭 링크는 같은 대상이어도 stow가 foreign으로 보고 -R을 거부하며, 상대경로
# 링크도 패키지 디렉토리가 옮겨져(예: zsh/ -> stow/zsh/) 더는 SRC를 가리키지 못하면
# 마찬가지로 거부한다(실측: stow 패키지 이관 직후 재현). readlink -f는 대상이 없어도
# (끊어진 링크) 경로를 정규화하므로 broken 여부와 무관하게 비교 가능하다.
#
# [실측 사고 기록] 이 함수를 예전엔 실제(비-심볼릭) 디렉토리에도 그대로 적용했었다.
# .githooks처럼 그 패키지 전용 디렉토리라면 안전하지만, ~/.config처럼 여러 앱이
# 공유하는 디렉토리는 "SRC와 다르면 백업" 조건이 항상 참이 되어 gh/infracost 등
# 무관한 실사용자 데이터를 통째로 날려버렸다. 그래서 디렉토리 대상은 반드시
# _reconcile_dir_symlink_only로만 다루고, 실제 디렉토리는 절대 건드리지 않는다 —
# GNU Stow 자신이 알아서 그 안으로 내려가 개별 파일만 심볼릭 링크한다.
_reconcile_symlink() {
  local target=$1 src=$2
  case "$(readlink "$target")" in
  /*)
    mkdir -p "$(dirname "$target")"
    mv "$target" "$target.backup.$BACKUP_TIMESTAMP"
    ;;
  *)
    if [ "$(_canonicalize "$target")" != "$(_canonicalize "$src")" ]; then
      mkdir -p "$(dirname "$target")"
      mv "$target" "$target.backup.$BACKUP_TIMESTAMP"
    fi
    ;;
  esac
}

# GNU Stow는 ~/.githooks처럼 대상 디렉토리가 없으면 파일 단위가 아니라 디렉토리 자체를
# 통째로 심볼릭 링크한다(tree-folding). 아래 파일 루프만으로는 그 링크를 못 만나므로
# 디렉토리 단위로 먼저 정리하되, 반드시 "이미 심볼릭 링크인 경우"만 다룬다 — 실제
# 디렉토리(예: ~/.config)는 다른 앱과 공유 중일 수 있어 절대 손대지 않는다.
while IFS= read -r -d '' SRC_DIR; do
  REL_PATH="${SRC_DIR#"$DOTFILES_DIR/$PKG/"}"
  TARGET="$HOME_DIR/$REL_PATH"
  [ -L "$TARGET" ] && _reconcile_symlink "$TARGET" "$SRC_DIR"
done < <(find "$DOTFILES_DIR/$PKG" -mindepth 1 -type d -print0)

# 파일은 심볼릭 링크 정리 + "실제 파일이 그 경로를 차지하고 있는" 진짜 충돌까지 다룬다.
while IFS= read -r -d '' SRC_FILE; do
  REL_PATH="${SRC_FILE#"$DOTFILES_DIR/$PKG/"}"
  TARGET="$HOME_DIR/$REL_PATH"
  if [ -L "$TARGET" ]; then
    _reconcile_symlink "$TARGET" "$SRC_FILE"
  elif [ -e "$TARGET" ] && [ "$(_canonicalize "$TARGET")" != "$(_canonicalize "$SRC_FILE")" ]; then
    mkdir -p "$(dirname "$TARGET")"
    mv "$TARGET" "$TARGET.backup.$BACKUP_TIMESTAMP"
  fi
done < <(find "$DOTFILES_DIR/$PKG" -type f -print0)
exit 0

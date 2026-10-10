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

# Backup paths are resolved relative to a no-follow parent dirfd by Python.
# Revalidating a string path here would leave a race between check and mv.
_safe_backup() {
  python3 "$(dirname "${BASH_SOURCE[0]}")/stow-safe-backup.py" \
    "$HOME_DIR" "$1" "$BACKUP_TIMESTAMP"
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
    _safe_backup "$target"
    ;;
  *)
    if [ "$(_canonicalize "$target")" != "$(_canonicalize "$src")" ]; then
      _safe_backup "$target"
    fi
    ;;
  esac
}

# GNU Stow는 ~/.githooks처럼 대상 디렉토리가 없으면 파일 단위가 아니라 디렉토리 자체를
# 통째로 심볼릭 링크한다(tree-folding). 아래 파일 루프만으로는 그 링크를 못 만나므로
# 디렉토리 단위로 먼저 정리한다. 다만 ~/.config -> ~/config-store처럼 사용자가 공유 부모
# 디렉토리를 외부의 "살아있는 디렉토리"로 연결해 둔 경우까지 자동 takeover하면, 그 아래의
# 무관한 앱 설정 전체가 기존 경로에서 이탈한다. 이런 링크는 그대로 보존하고 fail-closed한다.
# 반면 끊어진 과거 Stow 디렉토리 링크는 기존처럼 백업해 새 배치를 복구할 수 있게 한다.
_assert_dir_symlink_safe() {
  local target=$1 src=$2
  if [ -d "$target" ] && [ "$(_canonicalize "$target")" != "$(_canonicalize "$src")" ]; then
    echo "❌ [Hard Block] 외부 디렉토리 심볼릭 링크를 자동 교체하지 않습니다: $target -> $(readlink "$target")" >&2
    return 1
  fi
}

_reconcile_dir_symlink() {
  local target=$1 src=$2
  _assert_dir_symlink_safe "$target" "$src" || return 1
  # Historical Stow tree-folded directory symlinks must become real parent
  # directories under --no-folding. -R can unlink a concurrently replaced
  # user file; instead preserve the old link with the fd-based backup helper
  # before safe stow-only (-S) installation of individual leaf links.
  _safe_backup "$target"
}

# Bash process substitution hides the exit code of find. Inventory *both*
# lists before moving any user file: a partial scan must fail closed instead
# of leaving a half-migrated home directory.
STOW_INVENTORY=$(mktemp -d)
trap 'rm -rf "$STOW_INVENTORY"' EXIT
if [ -L "$DOTFILES_DIR" ] || [ -L "$DOTFILES_DIR/$PKG" ] || [ ! -d "$DOTFILES_DIR/$PKG" ]; then
  echo "❌ [Hard Block] 안전 설치기가 사용할 수 없는 Stow 소스 경로: $DOTFILES_DIR/$PKG" >&2
  exit 1
fi
if ! find "$DOTFILES_DIR/$PKG" -mindepth 1 -type d -print0 >"$STOW_INVENTORY/dirs"; then
  echo "❌ [Hard Block] Stow 소스 탐색 실패 (directories): $DOTFILES_DIR/$PKG" >&2
  exit 1
fi
if ! find "$DOTFILES_DIR/$PKG" -type f -print0 >"$STOW_INVENTORY/files"; then
  echo "❌ [Hard Block] Stow 소스 탐색 실패 (files): $DOTFILES_DIR/$PKG" >&2
  exit 1
fi

# stow-safe-install.py rejects source symlinks and other nonregular entries
# before installation. Detect the same unsupported types before *any* user
# file is backed up; find -type f/-type d would otherwise silently omit them.
if ! find "$DOTFILES_DIR/$PKG" -mindepth 1 ! -type d ! -type f -print0 >"$STOW_INVENTORY/unsupported"; then
  echo "❌ [Hard Block] Stow 소스 유형 탐색 실패: $DOTFILES_DIR/$PKG" >&2
  exit 1
fi
if [ -s "$STOW_INVENTORY/unsupported" ]; then
  IFS= read -r -d '' UNSUPPORTED_SOURCE <"$STOW_INVENTORY/unsupported" || true
  echo "❌ [Hard Block] 안전 설치기가 지원하지 않는 Stow 소스 항목: $UNSUPPORTED_SOURCE" >&2
  exit 1
fi

# Stow may ignore source files/directories via built-in, global or per-package
# regexes. Backing up those targets would remove user files that Stow will
# deliberately never replace. Ask Stow's own Perl matcher before ANY mv.
# If discovery or matching fails, keep the original HOME paths untouched.
if ! HOME="$HOME_DIR" perl "$(dirname "${BASH_SOURCE[0]}")/stow-filter-inventory.pl" \
  "$DOTFILES_DIR" "$PKG" "$HOME_DIR" "$DOTFILES_DIR/$PKG/" \
  "$STOW_INVENTORY/dirs" "$STOW_INVENTORY/files" \
  "$STOW_INVENTORY/filtered-dirs" "$STOW_INVENTORY/filtered-files"; then
  echo "❌ [Hard Block] GNU Stow ignore 판정에 실패했습니다: $PKG" >&2
  exit 1
fi
mv "$STOW_INVENTORY/filtered-dirs" "$STOW_INVENTORY/dirs"
mv "$STOW_INVENTORY/filtered-files" "$STOW_INVENTORY/files"

# A Stow source file must not displace an existing user directory, including
# a symlink to a live directory. Reject collisions across the whole file list
# *before* moving any existing entries, so a late collision is fail-closed.
while IFS= read -r -d '' SRC_FILE; do
  REL_PATH="${SRC_FILE#"$DOTFILES_DIR/$PKG/"}"
  TARGET="$HOME_DIR/$REL_PATH"
  if [ -d "$TARGET" ]; then
    echo "❌ [Hard Block] Stow 파일 경로에 사용자 디렉토리가 존재합니다: $TARGET" >&2
    exit 1
  fi
done <"$STOW_INVENTORY/files"

# Preflight every source directory before any backup move. If a directory
# is needed at TARGET but an existing user file (or live file symlink) occupies
# that path, Stow cannot create the directory. Do not move other user files
# first and then fail during Stow's conflict check.
# Existing foreign directory symlinks remain protected by the check below.
while IFS= read -r -d '' SRC_DIR; do
  REL_PATH="${SRC_DIR#"$DOTFILES_DIR/$PKG/"}"
  TARGET="$HOME_DIR/$REL_PATH"
  if [ -e "$TARGET" ] && [ ! -d "$TARGET" ]; then
    echo "❌ [Hard Block] Stow 디렉토리 경로에 사용자 파일이 존재합니다: $TARGET" >&2
    exit 1
  fi
  if [ -L "$TARGET" ]; then
    _assert_dir_symlink_safe "$TARGET" "$SRC_DIR" || exit 1
  fi
done <"$STOW_INVENTORY/dirs"

while IFS= read -r -d '' SRC_DIR; do
  REL_PATH="${SRC_DIR#"$DOTFILES_DIR/$PKG/"}"
  TARGET="$HOME_DIR/$REL_PATH"
  [ -L "$TARGET" ] && _reconcile_dir_symlink "$TARGET" "$SRC_DIR"
done <"$STOW_INVENTORY/dirs"

# 파일은 심볼릭 링크 정리 + "실제 파일이 그 경로를 차지하고 있는" 진짜 충돌까지 다룬다.
while IFS= read -r -d '' SRC_FILE; do
  REL_PATH="${SRC_FILE#"$DOTFILES_DIR/$PKG/"}"
  TARGET="$HOME_DIR/$REL_PATH"
  if [ -L "$TARGET" ]; then
    _reconcile_symlink "$TARGET" "$SRC_FILE"
  elif [ -e "$TARGET" ] && [ "$(_canonicalize "$TARGET")" != "$(_canonicalize "$SRC_FILE")" ]; then
    _safe_backup "$TARGET"
  fi
done <"$STOW_INVENTORY/files"
exit 0

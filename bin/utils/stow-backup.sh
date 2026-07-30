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

while IFS= read -r -d '' SRC_FILE; do
  REL_PATH="${SRC_FILE#"$DOTFILES_DIR/$PKG/"}"
  TARGET="$HOME_DIR/$REL_PATH"
  if [ -e "$TARGET" ] && [ ! -L "$TARGET" ] && [ "$(_canonicalize "$TARGET")" != "$(_canonicalize "$SRC_FILE")" ]; then
    mkdir -p "$(dirname "$TARGET")"
    mv "$TARGET" "$TARGET.backup.$BACKUP_TIMESTAMP"
  fi
done < <(find "$DOTFILES_DIR/$PKG" -type f -print0)
exit 0

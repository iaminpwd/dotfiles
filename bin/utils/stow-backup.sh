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
  if [ -L "$TARGET" ]; then
    # GNU Stow는 자기가 생성한 상대경로 심볼릭 링크만 "소유"로 인식한다. 절대경로
    # 심볼릭 링크는 설령 같은 파일을 가리켜도 stow가 foreign으로 판단해 -R을 거부하므로
    # (실측: 예전 방식으로 절대경로 링크된 mise/.config/mise/config.toml에서 재현),
    # 형식만 다른 경우도 미리 정리해 stow가 자기 형식으로 다시 만들게 한다.
    case "$(readlink "$TARGET")" in
    /*)
      mkdir -p "$(dirname "$TARGET")"
      mv "$TARGET" "$TARGET.backup.$BACKUP_TIMESTAMP"
      ;;
    esac
  elif [ -e "$TARGET" ] && [ "$(_canonicalize "$TARGET")" != "$(_canonicalize "$SRC_FILE")" ]; then
    mkdir -p "$(dirname "$TARGET")"
    mv "$TARGET" "$TARGET.backup.$BACKUP_TIMESTAMP"
  fi
done < <(find "$DOTFILES_DIR/$PKG" -type f -print0)
exit 0

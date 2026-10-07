#!/usr/bin/env bash
# .zshenv가 비대화형 zsh에도 사용자 실행 경로를 제공하는지 검증한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
ZSHENV="$ROOT/stow/zsh/.zshenv"

if ! command -v zsh >/dev/null 2>&1; then
  echo "[WARNING] SKIP zshenv-local-bin — zsh 미설치로 이 회귀가 수행되지 않았습니다"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
HOME_DIR="$TMP/home"
mkdir -p "$HOME_DIR/.local/bin" "$HOME_DIR/.local/share/mise/shims"

cp "$ZSHENV" "$HOME_DIR/.zshenv"

cat >"$HOME_DIR/.local/bin/mise" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$HOME_DIR/.local/bin/user-tool" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$HOME_DIR/.local/bin/mise" "$HOME_DIR/.local/bin/user-tool"

# 로그인/인터랙티브 초기화에 기대지 않고, 모든 zsh가 읽는 .zshenv만으로 확인한다.
# mise installer와 사용자의 일반 local command가 쓰는 ~/.local/bin 자체가 PATH에 있어야 한다.
# dotfiles의 내부 agent script를 global PATH에 배포하는 정책은 별개이며 현재 사용하지 않는다.
OUT=$(HOME="$HOME_DIR" PATH="/usr/bin:/bin" zsh -c '
  printf "mise=%s\n" "$(command -v mise || true)"
  printf "user=%s\n" "$(command -v user-tool || true)"
')

grep -qx "mise=$HOME_DIR/.local/bin/mise" <<<"$OUT"
grep -qx "user=$HOME_DIR/.local/bin/user-tool" <<<"$OUT"

echo "PASS: 비대화형 zsh에서도 일반 ~/.local/bin 사용자 실행 경로를 찾음"

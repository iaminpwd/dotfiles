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
cat >"$HOME_DIR/.local/bin/agent-edits-hook.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$HOME_DIR/.local/bin/mise" "$HOME_DIR/.local/bin/agent-edits-hook.sh"

# 로그인/인터랙티브 초기화에 기대지 않고, 모든 zsh가 읽는 .zshenv만으로 확인한다.
# bootstrap은 mise 본체와 ai_agent 실행 스크립트를 ~/.local/bin에 배치하므로,
# 기본 시스템 PATH에서 시작해도 둘 다 찾을 수 있어야 한다.
OUT=$(HOME="$HOME_DIR" PATH="/usr/bin:/bin" zsh -c '
  printf "mise=%s\n" "$(command -v mise || true)"
  printf "agent=%s\n" "$(command -v agent-edits-hook.sh || true)"
')

grep -qx "mise=$HOME_DIR/.local/bin/mise" <<<"$OUT"
grep -qx "agent=$HOME_DIR/.local/bin/agent-edits-hook.sh" <<<"$OUT"

echo "PASS: 비대화형 zsh에서도 ~/.local/bin의 mise와 agent 스크립트를 찾음"

#!/usr/bin/env bash
# verify-bootstrap-env.sh
# bootstrap.sh 실행 후 README의 성공 검증 커맨드가 약속하는 실제 환경 상태(도구 설치,
# stow 심볼릭 링크, AI 룰/스킬 주입)를 확인한다. exit code만으로는 "안 죽었다"만
# 증명될 뿐이라 별도로 필요.
#
# ci.yml의 bootstrap-smoke job이 멱등성 검증을 위해 이 스크립트를 1st run/2nd run
# 직후 각각 호출한다(동일 검증을 두 번 반복 호출해도 안전해야 함).

set -euo pipefail

export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"

# mise 도구 설치 확인
mise which shellcheck >/dev/null

# Stow symlink 확인
test -L "$HOME/.zshrc"
test -L "$HOME/.gitconfig"
test -L "$HOME/.vimrc"
test -L "$HOME/.tflint.hcl"
test -L "$HOME/.config/mise/config.toml"

# AI 글로벌 룰 주입 확인 (Gemini/Claude)
test -L "$HOME/.gemini/config/AGENTS.md"
test -L "$HOME/.claude/CLAUDE.md"
[ -s "$HOME/.gemini/config/AGENTS.md" ]

# 스킬 레지스트리 등록 확인
[ -n "$(ls -A "$HOME/.gemini/config/skills/" 2>/dev/null)" ]
[ -n "$(ls -A "$HOME/.claude/skills/" 2>/dev/null)" ]

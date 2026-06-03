#!/bin/bash
# 🚀 클라우드 인프라 엔지니어 한 방 세팅 (Troubleshooting 및 AI 브레인 연동 완료 버전)

# 오류 시 중단
set -e

# 1. 실행 경로 체크 (윈도우 마운트 경로에서 실행 방지)
if [[ "$(pwd)" == /mnt/c/* ]]; then
  echo "❌ 에러: /mnt/c/ (윈도우 경로)에서 실행 중입니다."
  echo "도트파일은 반드시 리눅스 네이티브 경로(예: ~/dotfiles)에 있어야 합니다."
  exit 1
fi

DOTFILES_DIR=$(pwd)

echo "[1/5] 필수 패키지 설치 중 (pipx 포함)..."
sudo apt update && sudo apt install -y git curl unzip wget zsh fzf jq stow pipx python3-venv

echo "[2/5] Oh My Zsh 및 플러그인 구성 중..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

ZSH_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}
[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] && git clone https://github.com/zsh-users/zsh-autosuggestions $ZSH_CUSTOM/plugins/zsh-autosuggestions
[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $ZSH_CUSTOM/plugins/zsh-syntax-highlighting

sudo chsh -s $(which zsh) $USER

echo "[3/5] Stow 연결을 위한 기존 파일 정리 및 연결..."
# 백업 추가 (안전성 향상)
cp ~/.zshrc ~/.zshrc.backup 2>/dev/null || true
cp ~/.vimrc ~/.vimrc.backup 2>/dev/null || true
cp ~/.mise.toml ~/.mise.toml.backup 2>/dev/null || true

# Stow 충돌 방지를 위해 기존의 실제 파일들을 삭제 (바로가기가 생길 자리를 비워줌)
rm -f ~/.zshrc ~/.vimrc ~/.mise.toml

cd "$DOTFILES_DIR"
stow -R zsh vim mise

echo "[4/5] 도구 버전 관리자(mise) 설치 및 인프라 도구 일괄 설치..."
if ! command -v ~/.local/bin/mise &> /dev/null; then
    curl https://mise.run | sh
fi

# Ansible 등을 위한 pipx 환경 반영
export PATH="$PATH:$HOME/.local/bin"

# PATH를 영구적으로 설정 (.zshrc에 추가)
# (주의: stow 연결 후이므로 dotfiles 안의 원본 .zshrc에 기록됨)
grep -qxF 'export PATH="$PATH:$HOME/.local/bin"' ~/.zshrc || echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.zshrc

# Mise 테스트
mise ls

echo "[5/5] 제미나이 AI 에이전트 인프라 표준 가이드라인 연결 중..."
# 기본 작업 공간 폴더 지정 (추후 task2, task3 등으로 변경 용이)
WORKSPACE_DIR="$HOME/task"

# 작업 공간 내부에 .gemini 폴더 안전하게 생성
mkdir -p "$WORKSPACE_DIR/.gemini"

# 최상위 룰 및 이그노어 링크 연결
ln -sf "$DOTFILES_DIR/GEMINI.md" "$WORKSPACE_DIR/GEMINI.md"
ln -sf "$DOTFILES_DIR/.geminiignore" "$WORKSPACE_DIR/.geminiignore"

# 세부 모듈 마크다운 표준 링크 연결
ln -sf "$DOTFILES_DIR/.gemini/agent-behavior.md" "$WORKSPACE_DIR/.gemini/agent-behavior.md"
ln -sf "$DOTFILES_DIR/.gemini/terraform-standard.md" "$WORKSPACE_DIR/.gemini/terraform-standard.md"
ln -sf "$DOTFILES_DIR/.gemini/ansible-standard.md" "$WORKSPACE_DIR/.gemini/ansible-standard.md"
ln -sf "$DOTFILES_DIR/.gemini/security-compliance.md" "$WORKSPACE_DIR/.gemini/security-compliance.md"
ln -sf "$DOTFILES_DIR/.gemini/code-review.md" "$WORKSPACE_DIR/.gemini/code-review.md"

echo "========================================================="
echo "✅ 완벽합니다! 모든 인프라 환경과 AI 브레인 설정이 완료되었습니다."
echo "💡 적용을 위해 터미널을 다시 열거나 'exec zsh'을 입력하세요."
echo "========================================================="
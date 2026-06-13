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

echo "[1/5] 필수 패키지 설치 중 (pipx 및 fd-find 포함)..."
sudo apt update && sudo apt install -y git curl unzip wget zsh fzf jq stow pipx python3-venv fd-find

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

# Mise 환경 신뢰 설정 및 도구 일괄 설치
mise trust ~/.mise.toml || true
mise install -y
mise ls

echo "[5/5] 제미나이 AI 에이전트 인프라 표준 가이드라인 동적 연결 중..."

# gemini 폴더 경로 변수화
GEMINI_BASE_DIR="$DOTFILES_DIR/gemini"

# gemini 폴더 하위의 모든 디렉토리를 순회 (예: cloud, kubernetes, terraform 등)
for TARGET_DIR in "$GEMINI_BASE_DIR"/*/; do
  # 디렉토리가 아닌 경우(glob 실패 등) 건너뜐다
  [ -d "$TARGET_DIR" ] || continue

  # 맨 뒤의 슬래시(/)를 제거하고 순수 폴더명만 추출 (예: 'cloud')
  ENV_NAME=$(basename "$TARGET_DIR")
  
  echo "=> [$ENV_NAME] 환경 AI 브레인 세팅 진행 중..."

  # 해당 환경의 GEMINI.md 최종 출력 경로
  MERGED_MD="$TARGET_DIR/GEMINI.md"
  rm -f "$MERGED_MD"

  # .gemini 폴더가 존재하는 경우에만 병합 수행
  if [ -d "$TARGET_DIR/.gemini" ]; then
    # bash의 기본 glob 확장 기능을 활용하여 사전순(00, 10, 20...) 정렬 처리
    for md_file in "$TARGET_DIR/.gemini/"*.md; do
      # .md 파일이 없을 경우 literal 문자열이 반환되는 것을 방지
      [ -f "$md_file" ] || continue
      
      echo "   Adding: $(basename "$md_file")"
      cat "$md_file" >> "$MERGED_MD"
      echo -e "\n\n" >> "$MERGED_MD"
    done
  fi

  # 작업 공간(Workspace) 동적 할당 및 생성 (예: ~/cloud, ~/kubernetes)
  WORKSPACE_DIR="$HOME/$ENV_NAME"
  mkdir -p "$WORKSPACE_DIR/src"

  # 심볼릭 링크 동적 생성 (파일이 실제로 존재할 때만 생성)
  if [ -f "$MERGED_MD" ]; then
    ln -sf "$MERGED_MD" "$WORKSPACE_DIR/GEMINI.md"
  fi
  
  if [ -f "$TARGET_DIR/.aiexclude" ]; then
    ln -sf "$TARGET_DIR/.aiexclude" "$WORKSPACE_DIR/.aiexclude"
  fi

  echo "   ✅ [$ENV_NAME] 세팅 완료 및 링크 생성 완료"
done

echo "========================================================="
echo "✅ 완벽합니다! 모든 인프라 환경과 AI 브레인 설정이 완료되었습니다."
echo "💡 적용을 위해 터미널을 다시 열거나 'exec zsh'을 입력하세요."
echo "========================================================="
#!/bin/bash
# 🚀 클라우드 인프라 엔지니어 한 방 세팅 (Troubleshooting 및 AI 브레인 연동 완료 버전)

# 오류 시 중단 (파이프라인 오류 및 미선언 변수 참조 포함)
set -euo pipefail

# 1. 실행 경로 체크 (윈도우 마운트 경로에서 실행 방지)
if [[ "$(pwd)" == /mnt/c/* ]]; then
  echo "❌ 에러: /mnt/c/ (윈도우 경로)에서 실행 중입니다."
  echo "도트파일은 반드시 리눅스 네이티브 경로(예: ~/dotfiles)에 있어야 합니다."
  exit 1
fi

# 스크립트가 실행된 위치와 무관하게 dotfiles 경로를 안전하게 가져옴
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[1/5] 필수 패키지 설치 중 (pipx 및 fd-find 포함)..."
sudo apt update && sudo apt install -y git curl unzip wget zsh fzf jq stow pipx python3-venv fd-find tree bat

echo "[2/5] Oh My Zsh 및 플러그인 구성 중..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

ZSH_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}
[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] && git clone https://github.com/zsh-users/zsh-autosuggestions $ZSH_CUSTOM/plugins/zsh-autosuggestions
[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $ZSH_CUSTOM/plugins/zsh-syntax-highlighting

if [ "$SHELL" != "$(which zsh)" ]; then
  sudo chsh -s $(which zsh) $USER
fi

echo "[3/5] Stow 연결을 위한 기존 파일 정리 및 연결..."
# 백업 추가 (안전성 향상)
cp ~/.zshrc ~/.zshrc.backup 2>/dev/null || true
cp ~/.vimrc ~/.vimrc.backup 2>/dev/null || true
cp ~/.mise.toml ~/.mise.toml.backup 2>/dev/null || true
cp ~/.gitconfig ~/.gitconfig.backup 2>/dev/null || true
cp ~/.gitignore_global ~/.gitignore_global.backup 2>/dev/null || true

# Stow 충돌 방지를 위해 기존의 실제 파일들을 삭제 (바로가기가 생길 자리를 비워줌)
rm -f ~/.zshrc ~/.vimrc ~/.mise.toml ~/.gitconfig ~/.gitignore_global

cd "$DOTFILES_DIR"
stow -t "$HOME" -R zsh vim mise git


echo "[4/5] 도구 버전 관리자(mise) 설치 및 인프라 도구 일괄 설치..."
if ! command -v ~/.local/bin/mise &> /dev/null; then
    curl https://mise.run | sh
fi

# Ansible 등을 위한 pipx 환경 반영
export PATH="$HOME/.local/bin:$PATH"

# Mise 환경 신뢰 설정 및 도구 일괄 설치 (절대 경로 호출로 안정성 확보)
~/.local/bin/mise trust ~/.mise.toml || true
~/.local/bin/mise install -y
~/.local/bin/mise ls

echo "[+] 보안 검증 도구(Checkov, Trufflehog) 추가 설치 중..."
# Checkov (IaC 보안 취약점 스캐너) - pipx로 격리 설치
pipx install checkov || echo "Checkov 설치 실패 또는 이미 존재함"
pipx install pre-commit || echo "pre-commit 설치 실패"
pipx install yamllint || echo "yamllint 설치 실패"
pipx ensurepath

# TruffleHog (시크릿 스캐너) - 로컬 bin에 바이너리 다운로드
curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b ~/.local/bin || echo "Trufflehog 설치 실패"

echo "[5/5] 제미나이 AI 에이전트 인프라 표준 가이드라인 동적 연결 중..."

# gemini 폴더 경로 변수화
GEMINI_BASE_DIR="$DOTFILES_DIR/gemini"

# gemini 폴더 하위의 모든 디렉토리를 순회 (예: aws, kubernetes, terraform 등)
for TARGET_DIR in "$GEMINI_BASE_DIR"/*/; do
  # 디렉토리가 아닌 경우(glob 실패 등) 건너뜐다
  [ -d "$TARGET_DIR" ] || continue

  # 맨 뒤의 슬래시(/)를 제거하고 순수 폴더명만 추출 (예: 'aws')
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

  # 작업 공간(Workspace) 동적 할당 및 생성 (예: ~/aws, ~/kubernetes)
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
echo "🎉 모든 기본 설치 및 환경 세팅이 백그라운드로 완료되었습니다!"
echo "마지막으로 사용자 맞춤 설정(선택)을 진행합니다."
echo "========================================================="

# 로컬 Git 설정
echo -e "\n[선택] Git 로컬 사용자 설정"
if [ ! -f ~/.gitconfig.local ]; then
    exec < /dev/tty
    echo "💡 입력을 원치 않으시면 아무것도 적지 않고 엔터(Enter)를 누르세요. 안전하게 스킵됩니다."
    read -p "=> 사용할 Git 이름 (예: Gildong Hong): " GIT_NAME
    read -p "=> 사용할 Git 이메일 (예: user@example.com): " GIT_EMAIL
    
    if [ -n "$GIT_NAME" ] && [ -n "$GIT_EMAIL" ]; then
        cat << EOF > ~/.gitconfig.local
[user]
    name = $GIT_NAME
    email = $GIT_EMAIL
EOF
        echo "✅ ~/.gitconfig.local 파일이 안전하게 생성되었습니다!"
    else
        echo "⏭️ 입력값이 없어 Git 설정을 건너뜁니다. 나중에 직접 파일을 만들어도 됩니다."
    fi
else
    echo "✅ 이미 ~/.gitconfig.local 파일이 존재하여 설정을 건너뜁니다."
fi

echo -e "\n[선택] 로컬 시크릿 환경 변수 파일 생성"
if [ ! -f ~/.zshrc.local ]; then
    cat << 'EOF' > ~/.zshrc.local
# =============================================================================
# 로컬 전용 시크릿 환경 변수 파일 (GitHub에 절대 커밋되지 않습니다)
# =============================================================================
# 이곳에 API Key나 보안 토큰을 export 하세요.
# 
# export GITHUB_TOKEN="your_github_token"
# export OPENAI_API_KEY="your_openai_api_key"
# export TF_VAR_db_password="your_secret_password"
EOF
    echo "✅ ~/.zshrc.local 파일이 안전하게 생성되었습니다! (시크릿 보관용)"
else
    echo "✅ 이미 ~/.zshrc.local 파일이 존재하여 설정을 건너뜁니다."
fi

echo "========================================================="
echo "✅ 완벽합니다! 모든 인프라 환경 구성이 진짜 완료되었습니다."
echo "💡 적용을 위해 터미널을 다시 열거나 'exec zsh'을 입력하세요."
echo "========================================================="
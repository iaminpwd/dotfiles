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

echo "[1/6] 필수 패키지 설치 중 (pipx 및 fd-find 포함)..."
sudo apt update && sudo apt install -y git curl unzip wget zsh stow pipx python3-venv fd-find dnsutils tree

echo "[2/6] Oh My Zsh 및 플러그인 구성 중..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

ZSH_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}
[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] && git clone https://github.com/zsh-users/zsh-autosuggestions $ZSH_CUSTOM/plugins/zsh-autosuggestions
[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $ZSH_CUSTOM/plugins/zsh-syntax-highlighting

if [ "$SHELL" != "$(which zsh)" ]; then
  sudo chsh -s $(which zsh) $USER
fi

echo "[3/6] Stow 연결을 위한 기존 파일 정리 및 연결..."
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


echo "[4/6] 도구 버전 관리자(mise) 설치 및 인프라 도구 일괄 설치..."
if ! command -v ~/.local/bin/mise &> /dev/null; then
    curl https://mise.run | sh
fi

# Ansible 등을 위한 pipx 환경 반영
export PATH="$HOME/.local/bin:$PATH"

# Mise 환경 신뢰 설정 및 도구 일괄 설치 (절대 경로 호출로 안정성 확보)
~/.local/bin/mise trust ~/.mise.toml || true
~/.local/bin/mise install -y
~/.local/bin/mise ls

echo "[+] Helm 플러그인 설치 중 (helm-diff)..."
export PATH="$HOME/.local/share/mise/shims:$PATH"
helm plugin install https://github.com/databus23/helm-diff --verify=false || echo "helm-diff 플러그인이 이미 설치되어 있거나 실패했습니다."



echo "[5/6] 제미나이 AI 에이전트 인프라 표준 가이드라인 동적 연결 중..."

CONTEXTS_DIR="$DOTFILES_DIR/contexts"

# 모든 컨텍스트 디렉토리를 순회하여 환경 설정 (스킬 동적 배포 포함)
for TARGET_DIR in "$CONTEXTS_DIR"/*/; do
  [ -d "$TARGET_DIR" ] || continue
  ENV_NAME=$(basename "$TARGET_DIR")

  echo "=> [$ENV_NAME] 기본 컨텍스트 파일 셋업 중..."

  # .contexts 폴더가 존재하는 경우에만 수행
  if [ -d "$TARGET_DIR/.contexts" ]; then
    # [NEW] 자동 심볼릭 링크 생성 (새 워크스페이스 추가 시 SSOT 마스터 000 코어 연결)
    if [ "$ENV_NAME" != "dotfiles" ]; then
      ln -sf "../../000-universal-core.md" "$TARGET_DIR/.contexts/000-universal-core.md"
    fi

    # [NEW] 공통 .aiexclude 베이스 템플릿 복사 (존재하지 않을 경우에만, 멱등성 유지)
    if [ -f "$CONTEXTS_DIR/.base.aiexclude" ] && [ ! -f "$TARGET_DIR/.aiexclude" ]; then
      cp "$CONTEXTS_DIR/.base.aiexclude" "$TARGET_DIR/.aiexclude"
      echo "   Adding Base: .aiexclude"
    fi
  fi

  # [NEW] AI 스킬 동적 매칭을 위한 SKILL.md 자동 생성 (존재하지 않을 경우)
  if [ ! -f "$TARGET_DIR/SKILL.md" ] && [ "$ENV_NAME" != "dotfiles" ] && [ "$ENV_NAME" != "basic" ]; then
    cat << EOF > "$TARGET_DIR/SKILL.md"
---
name: $ENV_NAME
description: $ENV_NAME 환경의 아키텍처, 인프라 배포, 트러블슈팅 및 보안 정책 컨텍스트
---
# $ENV_NAME Skill

이 스킬은 $ENV_NAME 관련 작업 시 발동됩니다.
상세한 가이드라인 및 규칙은 \`.contexts/\` 디렉토리 내부의 문서들을 참조하십시오.
EOF
    echo "   Adding Base: SKILL.md for $ENV_NAME"
  fi

  # 단일 워크스페이스(Workspace) 동적 할당 및 생성 (예: ~/workspace/aws)
  if [ "$ENV_NAME" != "dotfiles" ]; then
    WORKSPACE_DIR="$HOME/workspace/$ENV_NAME"
    mkdir -p "$WORKSPACE_DIR/src"
  fi

  echo "   ✅ [$ENV_NAME] 룰북 빌드 및 스킬 동적 배포 완료"
done

# 글로벌 AI 룰셋 링크 주입 (새 PC 환경 셋업용)
echo "=> [AI Global Rules] 글로벌 AGENTS.md 링크 주입 중..."
mkdir -p "$HOME/.gemini/config"
ln -sfn "$CONTEXTS_DIR/000-universal-core.md" "$HOME/.gemini/config/AGENTS.md"
echo "   ✅ 글로벌 룰 세팅 완료: ~/.gemini/config/AGENTS.md"



echo "[6/6] 시크릿 유출 스캔 및 보안 훅(Hook) 구성..."
export PATH="$HOME/.local/share/mise/shims:$PATH"
if command -v trufflehog &> /dev/null; then
  echo "=> 로컬 dotfiles 디렉토리 시크릿 검증 중..."
  trufflehog filesystem "$DOTFILES_DIR" --no-update || echo "⚠️ 경고: 시크릿 유출 의심 내역이 발견되었습니다. 즉시 확인 바랍니다."
else
  echo "⚠️ trufflehog를 찾을 수 없어 스캔을 건너뜁니다."
fi

# Pre-commit 훅 생성
mkdir -p "$DOTFILES_DIR/.git/hooks"
cat << 'EOF' > "$DOTFILES_DIR/.git/hooks/pre-commit"
#!/bin/bash
if command -v trufflehog &> /dev/null; then
  echo "🔒 커밋 전 시크릿 스캔을 수행합니다..."
  trufflehog filesystem "$(pwd)" --no-update --fail || { echo "❌ 시크릿 유출이 발견되어 커밋이 차단되었습니다."; exit 1; }
fi
EOF
chmod +x "$DOTFILES_DIR/.git/hooks/pre-commit"
echo "   ✅ Git pre-commit 훅(trufflehog) 구성 완료"


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
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

echo "[1/6] 필수 패키지 설치 여부 검증 및 설치 중 (pipx 및 fd-find 포함)..."
PACKAGES="git curl unzip wget zsh stow pipx python3-venv fd-find dnsutils tree"
if ! dpkg -s $PACKAGES >/dev/null 2>&1; then
  sudo apt update && sudo apt install -y $PACKAGES
fi

# Docker 설치 및 사용자 권한 설정 (Best Practice: 공식 Convenience Script 활용)
if ! command -v docker &> /dev/null; then
  echo "=> 최신 Docker Engine(docker-ce)을 공식 레포지토리에서 설치합니다..."
  curl -fsSL https://get.docker.com | sudo sh
fi

if systemctl list-unit-files | grep -qw "docker.service"; then
  sudo systemctl enable --now docker
  if ! groups "$USER" | grep -qw "docker"; then
    echo "=> 현재 사용자를 docker 그룹에 추가합니다..."
    sudo usermod -aG docker "$USER"
    echo "💡 안내: Docker 그룹 권한이 부여되었습니다. 적용을 위해 터미널 재시작 또는 'newgrp docker'가 필요합니다."
  fi
fi

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
cp -n ~/.zshrc ~/.zshrc.backup 2>/dev/null || true
cp -n ~/.vimrc ~/.vimrc.backup 2>/dev/null || true
cp -n ~/.mise.toml ~/.mise.toml.backup 2>/dev/null || true
cp -n ~/.gitconfig ~/.gitconfig.backup 2>/dev/null || true
cp -n ~/.gitignore_global ~/.gitignore_global.backup 2>/dev/null || true

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
if ! helm plugin list | grep -q "^diff"; then
  helm plugin install https://github.com/databus23/helm-diff --verify=false || echo "helm-diff 플러그인 설치 실패"
else
  echo "helm-diff 플러그인이 이미 설치되어 있습니다."
fi



echo "[5/6] 사용자 워크스페이스 생성 및 제미나이 AI 글로벌 룰셋 등록 중..."

CONTEXTS_DIR="$DOTFILES_DIR/contexts"

# 사용자 실제 작업용 기본 워크스페이스 폴더 생성
mkdir -p "$HOME/workspace"
echo "   ✅ 기본 워크스페이스 생성 완료: ~/workspace"

# 글로벌 AI 룰셋 링크 주입 (새 PC 환경 셋업용)
echo "=> [AI Global Rules] 글로벌 AGENTS.md 링크 주입 중..."
mkdir -p "$HOME/.gemini/config"
ln -sfn "$CONTEXTS_DIR/000-universal-core.md" "$HOME/.gemini/config/AGENTS.md"
echo "   ✅ 글로벌 룰 세팅 완료: ~/.gemini/config/AGENTS.md"

ln -sfn "$CONTEXTS_DIR/.base.aiexclude" "$HOME/.gemini/config/.aiexclude"
echo "   ✅ 글로벌 AI 제외 목록(aiexclude) 세팅 완료: ~/.gemini/config/.aiexclude"

echo "=> [AI Global Rules] 글로벌 스킬 레지스트리(skills.json) 동적 생성 중..."
SKILLS_JSON="$HOME/.gemini/config/skills.json"
echo '{' > "$SKILLS_JSON"
echo '  "entries": [' >> "$SKILLS_JSON"

# 모든 컨텍스트 디렉토리 스캔 및 JSON 엔트리 생성
entries=()
for TARGET_DIR in "$CONTEXTS_DIR"/*/; do
  [ -d "$TARGET_DIR" ] || continue
  ENV_NAME="$(basename "${TARGET_DIR%/}")"
  
  # dotfiles 컨텍스트는 글로벌 등록에서 제외
  if [ "$ENV_NAME" = "dotfiles" ]; then
    continue
  fi
  
  entries+=("    { \"path\": \"$DOTFILES_DIR/contexts/$ENV_NAME\" }")
done

# 콤마 분리 처리 (마지막 요소 제외)
for i in "${!entries[@]}"; do
  if [ $i -lt $((${#entries[@]} - 1)) ]; then
    echo "${entries[$i]}," >> "$SKILLS_JSON"
  else
    echo "${entries[$i]}" >> "$SKILLS_JSON"
  fi
done

echo '  ]' >> "$SKILLS_JSON"
echo '}' >> "$SKILLS_JSON"
echo "   ✅ 글로벌 스킬 레지스트리 생성 완료: $SKILLS_JSON"

echo "=> [AI Local Rules] 워크스페이스 전용 로컬 스킬(.agents/skills.json) 동적 생성 중..."
LOCAL_AGENTS_DIR="$DOTFILES_DIR/.agents"
mkdir -p "$LOCAL_AGENTS_DIR"
cat << 'EOF' > "$LOCAL_AGENTS_DIR/skills.json"
{
  "_comment": "이 워크스페이스(dotfiles) 전용 스킬 등록 파일. 스킬 발동 시 전역 룰을 무시하고 contexts/dotfiles 내부의 전용 프롬프트를 따릅니다.",
  "entries": [
    { "path": "contexts/dotfiles" }
  ]
}
EOF
echo "   ✅ 로컬 스킬 레지스트리 생성 완료: $LOCAL_AGENTS_DIR/skills.json"


echo "[6/6] 시크릿 유출 스캔 및 보안 훅(Hook) 구성..."
if command -v trufflehog &> /dev/null; then
  echo "=> 로컬 dotfiles 디렉토리 시크릿 검증 중..."
  trufflehog filesystem "$DOTFILES_DIR" --exclude-paths="$DOTFILES_DIR/.git" --no-update || echo "⚠️ 경고: 시크릿 유출 의심 내역이 발견되었습니다. 즉시 확인 바랍니다."
else
  echo "⚠️ trufflehog를 찾을 수 없어 스캔을 건너뜁니다."
fi

# Pre-commit 훅 생성
mkdir -p "$DOTFILES_DIR/.git/hooks"
cat << 'EOF' > "$DOTFILES_DIR/.git/hooks/pre-commit"
#!/bin/bash
if command -v trufflehog &> /dev/null; then
  echo "🔒 커밋 전 시크릿 스캔을 수행합니다 (이번에 변경된 파일만 검사합니다)..."
  
  # 새로 추가되거나 수정된 파일 목록 추출
  STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)
  
  if [ -z "$STAGED_FILES" ]; then
    exit 0
  fi
  
  # [보안 패치] 디스크 삭제 후 스테이징 메모리 잔류 취약점 방어
  for FILE in $STAGED_FILES; do
    if [ ! -f "$FILE" ]; then
      echo "❌ 보안 에러: '$FILE' 파일이 디스크에 존재하지 않지만 Git 스테이징 대기열에는 남아있습니다."
      echo "   (만약 시크릿 유출을 피하려고 디스크에서 파일을 지우셨다면,"
      echo "    반드시 'git rm --cached $FILE' 명령어로 Git 캐시에서도 완전히 지워야 합니다!)"
      exit 1
    fi
  done
  
  # 전체가 아닌 변경된 파일만 스캔 (엄청 빠름)
  trufflehog filesystem $STAGED_FILES --no-update --fail || { echo "❌ 시크릿 유출이 발견되어 커밋이 차단되었습니다."; exit 1; }
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
    if [ -t 0 ]; then
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
        echo "⏭️ 비대화형(CI/CD) 터미널로 인식되어 Git 설정을 스킵합니다."
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
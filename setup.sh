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

echo "[1/6] 필수 패키지 설치 여부 검증 및 설치 중 (pipx 포함)..."
PACKAGES=(git curl unzip wget zsh stow pipx python3-venv dnsutils tree)
if ! dpkg -s "${PACKAGES[@]}" >/dev/null 2>&1; then
  sudo apt update && sudo apt install -y "${PACKAGES[@]}"
fi

# Docker 설치 및 사용자 권한 설정 (Best Practice: 공식 Convenience Script 활용)
if ! command -v docker &>/dev/null; then
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
  # sh -c "$(curl ...)" 형태는 curl이 네트워크 오류로 실패해도 sh -c ""(빈 명령)가 성공으로
  # 처리되어 set -e가 실패를 감지하지 못한다. 다운로드를 별도 임시 파일로 받아 curl의
  # 종료 코드를 직접 검사해야 네트워크 타임아웃 같은 실패를 확실히 잡아낼 수 있다.
  OMZ_INSTALLER=$(mktemp)
  trap 'rm -f "$OMZ_INSTALLER"' EXIT
  if ! curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$OMZ_INSTALLER"; then
    echo "❌ 에러: Oh My Zsh 설치 스크립트 다운로드에 실패했습니다 (네트워크 확인 필요)." >&2
    exit 1
  fi
  sh "$OMZ_INSTALLER" "" --unattended
  rm -f "$OMZ_INSTALLER"
  trap - EXIT
fi

ZSH_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}
[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] && git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] && git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

if [ "$SHELL" != "$(which zsh)" ]; then
  sudo chsh -s "$(which zsh)" "$USER"
fi

echo "[3/6] Stow 연결을 위한 기존 파일 정리 및 연결..."
# 1. contexts, assets, temp_ 등으로 시작하거나 숨김 폴더가 아닌 디렉토리 목록을 동적으로 Stow 패키지로 자동 획득
STOW_PKGS=()
for d in */; do
  [ -d "$d" ] || continue
  d_name="${d%/}"
  if [[ "$d_name" != "contexts" && "$d_name" != "assets" && "$d_name" != "temp_"* && "$d_name" != "."* ]]; then
    STOW_PKGS+=("$d_name")
  fi
done

echo "   => 감지된 Stow 패키지: ${STOW_PKGS[*]}"

# 각 stow 패키지 하위의 모든 실제 파일을 자동 순회하며 백업 후 정리
for PKG in "${STOW_PKGS[@]}"; do
  while IFS= read -r -d '' SRC_FILE; do
    REL_PATH="${SRC_FILE#"$DOTFILES_DIR/$PKG/"}"
    TARGET="$HOME/$REL_PATH"
    # 심볼릭 링크가 아닌 실제 파일이 이미 존재할 때만 백업 후 정리 (stow 충돌 방지)
    # 단, TARGET의 상위 디렉토리 자체가 이미 stow로 심볼릭 링크되어 있으면(예: ~/.githooks ->
    # dotfiles/git/.githooks) 그 안의 리프 파일은 -L 검사에 걸리지 않아 소스 파일 자기 자신을
    # "충돌하는 실제 파일"로 오인하게 되고, 그 상태로 cp/rm을 실행하면 원본 소스 파일이 그대로
    # 삭제되는 사고로 이어진다. TARGET의 실제 경로가 소스 파일과 동일하면(이미 올바르게 연결된
    # 상태) 건드리지 않도록 realpath 비교를 추가한다.
    if [ -e "$TARGET" ] && [ ! -L "$TARGET" ] && [ "$(readlink -f "$TARGET")" != "$(readlink -f "$SRC_FILE")" ]; then
      mkdir -p "$(dirname "$TARGET")"
      cp -n "$TARGET" "$TARGET.backup" 2>/dev/null || true
      rm -f "$TARGET"
    fi
  done < <(find "$DOTFILES_DIR/$PKG" -type f -print0)
done

cd "$DOTFILES_DIR"
stow -t "$HOME" -R "${STOW_PKGS[@]}"

echo "[4/6] 도구 버전 관리자(mise) 설치 및 인프라 도구 일괄 설치..."
if ! command -v ~/.local/bin/mise &>/dev/null; then
  # -fsSL: HTTP 오류(5xx 등) 시 curl이 오류 페이지를 sh로 흘리지 않고 실패하도록 강제
  # (Docker 설치 라인과 동일한 방어 패턴 — set -o pipefail이 이 실패를 감지해 중단시킨다)
  curl -fsSL https://mise.run | sh
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

echo "[5/6] 사용자 워크스페이스 생성 및 제미나이/클로드/Codex AI 글로벌 룰셋 등록 중..."

CONTEXTS_DIR="$DOTFILES_DIR/contexts"

# 사용자 실제 작업용 기본 워크스페이스 폴더 생성
mkdir -p "$HOME/workspace"
echo "   ✅ 기본 워크스페이스 생성 완료: ~/workspace"

# 제미나이 글로벌 AI 룰셋 링크 주입 (자동 감지용 skills 폴더 포함)
echo "=> [Gemini Rules] 제미나이 글로벌 AGENTS.md 링크 주입 중..."
mkdir -p "$HOME/.gemini/config/skills"
ln -sfn "$CONTEXTS_DIR/base.AGENTS.md" "$HOME/.gemini/config/AGENTS.md"
echo "   ✅ 제미나이 글로벌 룰 세팅 완료: ~/.gemini/config/AGENTS.md"

ln -sfn "$CONTEXTS_DIR/.base.aiexclude" "$HOME/.gemini/config/.aiexclude"
echo "   ✅ 제미나이 글로벌 AI 제외 목록(aiexclude) 세팅 완료: ~/.gemini/config/.aiexclude"

# Claude Code 글로벌 설정 추가 (CLAUDE.md 및 rules 디렉토리)
echo "=> [Claude Code Rules] 클로드 글로벌 CLAUDE.md 링크 주입 중..."
mkdir -p "$HOME/.claude/rules"
ln -sfn "$CONTEXTS_DIR/base.AGENTS.md" "$HOME/.claude/CLAUDE.md"
echo "   ✅ 클로드 글로벌 룰 세팅 완료: ~/.claude/CLAUDE.md"

# 클로드 커밋/PR 어트리뷰션 비활성화 (Co-Authored-By: Claude 트레일러 및 PR 푸터 제거)
# 사용자가 이미 설정해둔 다른 값(effortLevel 등)을 보존하기 위해 덮어쓰기 대신 jq로 병합한다
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
[ -f "$CLAUDE_SETTINGS" ] || echo '{}' >"$CLAUDE_SETTINGS"
if jq empty "$CLAUDE_SETTINGS" 2>/dev/null; then
  CLAUDE_SETTINGS_TMP=$(mktemp)
  jq '.attribution.commit = "" | .attribution.pr = ""' "$CLAUDE_SETTINGS" >"$CLAUDE_SETTINGS_TMP"
  mv "$CLAUDE_SETTINGS_TMP" "$CLAUDE_SETTINGS"
  echo "   ✅ 클로드 커밋/PR 어트리뷰션(Co-Authored-By) 비활성화 완료: $CLAUDE_SETTINGS"
else
  echo "   ⚠️ $CLAUDE_SETTINGS 파일이 유효한 JSON이 아니어서 어트리뷰션 설정을 건너뜁니다. 파일을 직접 수정한 뒤 setup.sh를 다시 실행하세요."
fi

# Codex 글로벌 설정 추가 (AGENTS.md 및 skills 디렉토리)
echo "=> [Codex Rules] Codex 글로벌 AGENTS.md 링크 주입 중..."
mkdir -p "$HOME/.codex/skills"
ln -sfn "$CONTEXTS_DIR/base.AGENTS.md" "$HOME/.codex/AGENTS.md"
echo "   ✅ Codex 글로벌 룰 세팅 완료: ~/.codex/AGENTS.md"

ln -sfn "$CONTEXTS_DIR/.base.aiexclude" "$HOME/.codex/.aiexclude"
echo "   ✅ Codex 글로벌 AI 제외 목록(aiexclude) 세팅 완료: ~/.codex/.aiexclude"

# 모든 컨텍스트 디렉토리 스캔 및 각 AI 에이전트 글로벌 스킬 등록
echo "=> [AI Global Rules] 각 AI 에이전트 글로벌 스킬 등록 중..."
for TARGET_DIR in "$CONTEXTS_DIR"/*/; do
  [ -d "$TARGET_DIR" ] || continue
  ENV_NAME="$(basename "${TARGET_DIR%/}")"

  # dotfiles 컨텍스트는 글로벌 등록에서 제외 (글로벌 룰 오염 방지)
  if [ "$ENV_NAME" = "dotfiles" ]; then
    continue
  fi

  if [ -f "$TARGET_DIR/SKILL.md" ]; then
    # 1. 제미나이 (Gemini) 글로벌 스킬 등록 (자동 감지 디렉토리 연동 - 실시간 심볼릭 링크 구조)
    mkdir -p "$HOME/.gemini/config/skills/${ENV_NAME}"
    rm -f "$HOME/.gemini/config/skills/${ENV_NAME}/SKILL.md"
    ln -sfn "$TARGET_DIR/SKILL.md" "$HOME/.gemini/config/skills/${ENV_NAME}/SKILL.md"
    if [ -d "$TARGET_DIR/references" ]; then
      ln -sfn "$TARGET_DIR/references" "$HOME/.gemini/config/skills/${ENV_NAME}/references"
    fi
    echo "   ✅ 제미나이 글로벌 스킬 등록 완료 (자동 감지): ~/.gemini/config/skills/${ENV_NAME}/"

    # 2. 클로드 (Claude Code) 글로벌 스킬 등록 (순수 심볼릭 링크 연동)
    rm -f "$HOME/.claude/rules/${ENV_NAME}.md"
    ln -sfn "$TARGET_DIR/SKILL.md" "$HOME/.claude/rules/${ENV_NAME}.md"
    echo "   ✅ 클로드 글로벌 스킬 등록 완료: ~/.claude/rules/${ENV_NAME}.md"

    # 3. Codex 글로벌 스킬 등록 (순수 심볼릭 링크 연동)
    rm -f "$HOME/.codex/skills/${ENV_NAME}.md"
    ln -sfn "$TARGET_DIR/SKILL.md" "$HOME/.codex/skills/${ENV_NAME}.md"
    echo "   ✅ Codex 글로벌 스킬 등록 완료: ~/.codex/skills/${ENV_NAME}.md"
  fi
done

echo "=> [AI Local Rules] 워크스페이스 전용 로컬 규칙 링크 구성 중..."
# 로컬 루트 폴더 간결화 및 에이전트별 상시 자동 로드 100% 보장
# 제미나이용 AGENTS.md와 클로드용 CLAUDE.md 링크 파일 2개만 단독 생성 (.agents 폴더 완전 배제)
ln -sfn "$DOTFILES_DIR/contexts/dotfiles/SKILL.md" "$DOTFILES_DIR/AGENTS.md"
echo "   ✅ 제미나이 로컬 규칙 연동 완료: $DOTFILES_DIR/AGENTS.md"
ln -sfn "$DOTFILES_DIR/contexts/dotfiles/SKILL.md" "$DOTFILES_DIR/CLAUDE.md"
echo "   ✅ 클로드 로컬 규칙 연동 완료: $DOTFILES_DIR/CLAUDE.md"

echo "[6/6] 시크릿 유출 스캔 및 보안 훅(Hook) 구성..."
if command -v trufflehog &>/dev/null; then
  echo "=> 로컬 dotfiles 디렉토리 시크릿 검증 중..."
  trufflehog filesystem "$DOTFILES_DIR" --exclude-paths="$DOTFILES_DIR/.git" --no-update || echo "⚠️ 경고: 시크릿 유출 의심 내역이 발견되었습니다. 즉시 확인 바랍니다."
else
  echo "⚠️ trufflehog를 찾을 수 없어 스캔을 건너뜁니다."
fi

# Git 훅 구성 (dotfiles/git/.githooks가 Stow에 의해 ~/.githooks로 연동됨)
# 실행 권한 부여 (Stow로 이미 심볼릭 링크가 생성되었거나 생성될 예정이므로 원본에 권한 부여)
chmod +x "$DOTFILES_DIR/git/.githooks/pre-commit" "$DOTFILES_DIR/git/.githooks/commit-msg"

# 4. Git 전역 설정에 글로벌 훅 경로 활성화 등록 (이식성을 위해 물결표로 저장되도록 '~/.githooks' 명시 지정)
# shellcheck disable=SC2088 # 쉘이 아닌 git config 값으로 저장되는 문자열이며, '~'는 git이 읽는 시점에 자체 확장함
git config --global core.hooksPath "~/.githooks"
echo "   ✅ Git 글로벌 pre-commit 훅 연동 및 경로 지정 완료: ~/.githooks"

echo "========================================================="
echo "🎉 모든 기본 설치 및 환경 세팅이 백그라운드로 완료되었습니다!"
echo "마지막으로 사용자 맞춤 설정(선택)을 진행합니다."
echo "========================================================="

# 로컬 Git 설정
echo -e "\n[선택] Git 로컬 사용자 설정"
if [ ! -f ~/.gitconfig.local ]; then
  if [ -t 0 ]; then
    exec </dev/tty
    echo "💡 입력을 원치 않으시면 아무것도 적지 않고 엔터(Enter)를 누르세요. 안전하게 스킵됩니다."
    read -r -p "=> 사용할 Git 이름 (예: Gildong Hong): " GIT_NAME
    read -r -p "=> 사용할 Git 이메일 (예: user@example.com): " GIT_EMAIL

    if [ -n "$GIT_NAME" ] && [ -n "$GIT_EMAIL" ]; then
      cat <<EOF >~/.gitconfig.local
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
  cat <<'EOF' >~/.zshrc.local
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

echo -e "\n[선택] Infracost 비용 분석 도구 로그인"
if [ -t 0 ]; then
  # mise shim 및 local path 가용성 보장
  export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"

  if command -v infracost &>/dev/null; then
    if infracost configure get api_key 2>&1 | grep -q "No API key"; then
      echo "💡 Infracost API 키가 등록되어 있지 않습니다. 로컬 사전 비용 분석을 위해 로그인이 필요합니다."
      read -r -p "=> 지금 Infracost 로그인을 진행하시겠습니까? (y/N): " INFRACOST_CONFIRM
      if [[ "$INFRACOST_CONFIRM" =~ ^[Yy]$ ]]; then
        infracost auth login
      else
        echo "⏭️ Infracost 로그인을 건너뜁니다. 나중에 'infracost auth login'을 실행해 등록할 수 있습니다."
      fi
    else
      echo "✅ 이미 Infracost API 키가 등록되어 있어 로그인을 건너뜁니다."
    fi
  else
    echo "⚠️ infracost CLI가 현재 세션에서 인식되지 않아 로그인을 건너뜁니다."
  fi
else
  echo "⏭️ 비대화형(CI/CD) 터미널로 인식되어 Infracost 설정을 건너뜁니다."
fi

echo "========================================================="
echo "✅ 완벽합니다! 모든 인프라 환경 구성이 진짜 완료되었습니다."
echo "💡 적용을 위해 터미널을 다시 열거나 'exec zsh'을 입력하세요."
echo "========================================================="

#!/usr/bin/env bash
# bootstrap.sh
# 🚀 인프라 엔지니어 로컬 환경 셋업 진입점
# 필수 도구(mise, just, ansible)를 준비한 후 제어권을 Justfile과 Ansible Playbook으로 위임합니다.

set -euo pipefail
export ANSIBLE_HOME="$HOME/.cache/ansible"
# 실행 경로에 무관하게 스크립트 위치 기준 절대경로 확정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 1. OS 패키지 매니저 판별
# stow는 ansible의 packages 역할이 나중에 다시 설치하지만(멱등), mise config.toml을
# ansible보다 먼저 링크해야 해서(아래 3단계) 여기서 미리 확보해둔다.
if command -v apt-get &>/dev/null; then
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl git unzip stow
elif command -v dnf &>/dev/null; then
  sudo dnf install -y curl git unzip stow
elif command -v brew &>/dev/null; then
  # macOS는 기본 내장 도구 활용, stow만 별도 설치
  if ! command -v stow &>/dev/null; then
    brew install stow
  fi
else
  echo "❌ 지원하지 않는 운영체제/패키지 매니저입니다." >&2
  exit 1
fi

# 2. 도구 버전 관리자(mise) 설치
if [ ! -x "$HOME/.local/bin/mise" ]; then
  echo "=> Installing mise (https://mise.run)..."
  curl -fsSL https://mise.run | sh
fi

export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"

# 3. 글로벌 도구(Ansible, Just) 설치 (mise 활용)
echo "=> Installing Ansible & Just via mise & pipx..."
# ansible-core와 just는 pipx/직접 설치 패턴 대신, mise 환경(config.toml)에 위임하여 SSOT를 유지합니다.

echo "========================================================="
echo "=> 🚀 Running 'mise install' automatically..."
export PATH="$HOME/.local/bin:$PATH"
mkdir -p "$HOME/.config/mise"
# mise install이 ansible(및 그 안의 stow 역할)보다 먼저 필요해 GNU Stow로 미리
# 링크해둔다. ansible stow 역할이 나중에 같은 패키지를 다시 stow해도(-R은 멱등) 안전.
# 기존 사용자 파일이 있으면 stow-backup.sh로 먼저 백업한다.
bash "$SCRIPT_DIR/bin/utils/stow-backup.sh" mise "$SCRIPT_DIR" "$HOME"
(cd "$SCRIPT_DIR" && stow -t "$HOME" -R mise)
# uv를 먼저 단독 설치해 완료시켜야, 이후 병렬 설치되는 pipx 계열 도구(ansible 등)가
# 레이스 컨디션 없이 처음부터 uvx 경로를 타서 설치됨.
~/.local/bin/mise install -y uv
~/.local/bin/mise install -y

echo "========================================================="
echo "=> 🚀 Running 'just setup' automatically..."

if command -v trufflehog &>/dev/null; then
  echo "=> 로컬 dotfiles 디렉토리 시크릿 검증 중..."
  trufflehog filesystem "$SCRIPT_DIR" --no-update --fail || {
    echo "❌ [Hard Block] 시크릿 유출 의심 내역이 발견되어 즉시 작업을 중단합니다." >&2
    exit 1
  }
fi

chmod +x "$SCRIPT_DIR/git/.githooks/pre-commit" "$SCRIPT_DIR/git/.githooks/commit-msg" "$SCRIPT_DIR/git/.githooks/pre-push" 2>/dev/null || true

cd "$SCRIPT_DIR" || exit 1

if command -v just &>/dev/null; then
  just setup
elif [ -x "$HOME/.local/share/mise/shims/just" ]; then
  "$HOME/.local/share/mise/shims/just" setup
else
  ~/.local/bin/mise exec -- just setup
fi

echo ""
echo "========================================="
echo "📝 사용자 환경 설정을 시작합니다."
echo "========================================="

# 1. Git 사용자 설정 (.gitconfig.local)
if [ ! -f "$HOME/.gitconfig.local" ]; then
  # non-interactive(CI 등)로 stdin이 닫혀 있으면 read가 EOF로 exit 1을 반환해
  # set -e가 스크립트 전체를 죽인다. || true로 무시하고 아래 빈 값 분기로 넘긴다.
  read -r -p "Git 사용자 이름 (예: 홍길동): " git_name || true
  read -r -p "Git 이메일 주소: " git_email || true
  if [ -n "$git_name" ] && [ -n "$git_email" ]; then
    cat >"$HOME/.gitconfig.local" <<EOF
[user]
    name = $git_name
    email = $git_email
EOF
    echo "✅ ~/.gitconfig.local 생성 완료."
  else
    echo "⏭️ Git 설정 건너뜀 (추후 ~/.gitconfig.local 에 직접 설정 가능)"
  fi
else
  echo "✅ ~/.gitconfig.local 이 이미 존재합니다."
fi

# 2. 로컬 환경변수 파일 생성 (.zshrc.local)
if [ ! -f "$HOME/.zshrc.local" ]; then
  echo ""
  echo "🔒 시크릿 환경 변수 관리를 위한 ~/.zshrc.local 파일을 생성합니다."
  cat >"$HOME/.zshrc.local" <<EOF
# 로컬 전용 시크릿 환경 변수 및 오버라이드 설정
# 이 파일은 Git에 커밋되지 않아야 합니다. (.gitignore 규칙 확인)

# export GITHUB_TOKEN="your_token_here"
# export OPENAI_API_KEY="your_api_key_here"
EOF
  echo "✅ ~/.zshrc.local 생성 완료. (이 파일에 필요한 시크릿 값을 추가하세요)"
else
  echo "✅ ~/.zshrc.local 이 이미 존재합니다."
fi

# 3. Infracost 설정 연동 가이드
if [ -x "$HOME/.local/bin/mise" ]; then
  # infracost는 mise로 설치되었을 확률이 높으므로 런타임에서 호출 가능한지 확인
  if ~/.local/share/mise/shims/infracost --version &>/dev/null; then
    if [ ! -f "$HOME/.config/infracost/credentials.yml" ] || ! grep -q "api_key:" "$HOME/.config/infracost/credentials.yml" 2>/dev/null; then
      echo ""
      read -r -p "Infracost 인증을 바로 진행하시겠습니까? (y/N): " run_infracost || true
      if [[ "$run_infracost" =~ ^[Yy]$ ]]; then
        ~/.local/share/mise/shims/infracost auth login
      else
        echo "⏭️ Infracost 인증 건너뜀 (추후 'infracost auth login' 으로 진행)"
      fi
    else
      echo "✅ Infracost 인증이 이미 완료되어 있습니다."
    fi
  fi
fi

# 4. GitHub CLI(gh) 인증 - 프라이빗 레포 git clone 시 credential helper(gh auth git-credential)가 이 인증을 사용
if [ -x "$HOME/.local/bin/mise" ]; then
  # gh는 mise로 설치되었을 확률이 높으므로 런타임에서 호출 가능한지 확인
  if ~/.local/share/mise/shims/gh --version &>/dev/null; then
    if ! ~/.local/share/mise/shims/gh auth status &>/dev/null; then
      echo ""
      read -r -p "GitHub 로그인 인증을 바로 진행하시겠습니까? (브라우저 링크 방식) (y/N): " run_gh_auth || true
      if [[ "$run_gh_auth" =~ ^[Yy]$ ]]; then
        ~/.local/share/mise/shims/gh auth login
      else
        echo "⏭️ GitHub 인증 건너뜀 (추후 'gh auth login' 으로 진행)"
      fi
    else
      echo "✅ GitHub CLI 인증이 이미 완료되어 있습니다."
    fi
  fi
fi

echo "========================================================="
echo "✅ Bootstrap 및 전체 환경 셋업(Ansible & mise)이 성공적으로 완료되었습니다!"
echo "💡 변경된 환경 변수 및 쉘 환경을 적용하려면 'exec zsh' 를 실행하세요."
# ansible docker 롤의 안내 태스크는 다른 롤들 출력에 파묻혀 놓치기 쉬우므로,
# 실제로 눈에 띄는 스크립트 맨 마지막에 한 번 더 띄운다.
if [ "$(uname)" = "Darwin" ]; then
  echo "🐳 macOS는 Docker Engine을 네이티브로 설치할 수 없습니다."
  echo "   https://www.docker.com/products/docker-desktop 에서 Docker Desktop을 직접 설치하거나,"
  echo "   Colima/OrbStack 같은 경량 대안을 사용하십시오."
fi
echo "========================================================="

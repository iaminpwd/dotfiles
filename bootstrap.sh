#!/usr/bin/env bash
# bootstrap.sh
# 🚀 인프라 엔지니어 로컬 환경 셋업 진입점 (Ansible 마이그레이션 버전)
# 기존 750라인짜리 setup.sh를 대체하며, 핵심 도구(mise, just, ansible)만 설치 후
# 제어권을 Justfile과 Ansible Playbook으로 넘깁니다.

set -euo pipefail
export ANSIBLE_HOME="$HOME/.cache/ansible"
# 1. OS 패키지 매니저 판별
if command -v apt-get &>/dev/null; then
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl git unzip python3-venv pipx
elif command -v dnf &>/dev/null; then
  sudo dnf install -y curl git unzip pipx
elif command -v brew &>/dev/null; then
  # macOS는 기본 내장 도구 활용, pipx 설치
  if ! command -v pipx &>/dev/null; then
    brew install pipx
  fi
else
  echo "❌ 지원하지 않는 운영체제/패키지 매니저입니다." >&2
  exit 1
fi

# 2. 도구 버전 관리자(mise) 설치
if ! command -v ~/.local/bin/mise &>/dev/null; then
  echo "=> Installing mise (https://mise.run)..."
  curl -fsSL https://mise.run | sh
fi

export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"

# 3. 글로벌 도구(Ansible, Just) 설치 (mise 활용)
echo "=> Installing Ansible & Just via mise & pipx..."
~/.local/bin/mise use -g just
if ! command -v ansible-playbook &>/dev/null; then
  pipx install ansible-core
  pipx ensurepath
fi

echo "========================================================="
echo "=> 🚀 Running 'mise install' automatically..."
export PATH="$HOME/.local/bin:$PATH"
MISE_CONFIG_FILE="$(pwd)/mise/.config/mise/config.toml"
export MISE_CONFIG_FILE
~/.local/bin/mise install -y

echo "=> 🚀 Installing helm-diff plugin..."
if ! grep -q "^diff" <<<"$(helm plugin list 2>/dev/null || true)"; then
  helm plugin install https://github.com/databus23/helm-diff --verify=false || echo "helm-diff 플러그인 설치 실패"
else
  echo "helm-diff 플러그인이 이미 설치되어 있습니다."
fi

echo "========================================================="
echo "=> 🚀 Running 'just setup' automatically..."

if command -v trufflehog &>/dev/null; then
  echo "=> 로컬 dotfiles 디렉토리 시크릿 검증 중..."
  trufflehog git "file://$(pwd)" --no-update --fail || {
    echo "❌ [Hard Block] 시크릿 유출 의심 내역이 발견되어 즉시 작업을 중단합니다." >&2
    exit 1
  }
fi

chmod +x "$(pwd)/git/.githooks/pre-commit" "$(pwd)/git/.githooks/commit-msg" 2>/dev/null || true

just setup

echo ""
echo "========================================="
echo "📝 사용자 환경 설정을 시작합니다."
echo "========================================="

# 1. Git 사용자 설정 (.gitconfig.local)
if [ ! -f "$HOME/.gitconfig.local" ]; then
  read -r -p "Git 사용자 이름 (예: 홍길동): " git_name
  read -r -p "Git 이메일 주소: " git_email
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
if command -v ~/.local/bin/mise &>/dev/null; then
  # infracost는 mise로 설치되었을 확률이 높으므로 런타임에서 호출 가능한지 확인
  if ~/.local/share/mise/shims/infracost --version &>/dev/null; then
    echo ""
    read -r -p "Infracost 인증을 바로 진행하시겠습니까? (y/N): " run_infracost
    if [[ "$run_infracost" =~ ^[Yy]$ ]]; then
      ~/.local/share/mise/shims/infracost auth login
    else
      echo "⏭️ Infracost 인증 건너뜀 (추후 'infracost auth login' 으로 진행)"
    fi
  fi
fi

echo "========================================================="
echo "✅ Bootstrap 및 전체 환경 셋업(Ansible & mise)이 성공적으로 완료되었습니다!"
echo "========================================================="

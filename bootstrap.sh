#!/usr/bin/env bash
# bootstrap.sh
# 🚀 인프라 엔지니어 로컬 환경 셋업 진입점
# 필수 도구(mise, just, ansible)를 준비한 후 제어권을 Justfile과 Ansible Playbook으로 위임합니다.

set -euo pipefail
export ANSIBLE_HOME="$HOME/.cache/ansible"
# 실행 경로나 심볼릭 링크 체인에 무관하게 실제 저장소 루트를 찾는다.
# mise 설치 이전에 실행되므로 macOS 기본 BSD readlink와도 호환돼야 한다.
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  SOURCE_DIR=$(cd -P "$(dirname "$SOURCE")" && pwd)
  LINK_TARGET=$(readlink "$SOURCE")
  case "$LINK_TARGET" in
  /*) SOURCE="$LINK_TARGET" ;;
  *) SOURCE="$SOURCE_DIR/$LINK_TARGET" ;;
  esac
done
SCRIPT_DIR=$(cd -P "$(dirname "$SOURCE")" && pwd)

# Linux 최소 설치에서도 root 사용자는 sudo 없이 bootstrap할 수 있어야 한다.
# 일반 사용자는 sudo를 사용하고, 둘 다 불가능하면 command-not-found 대신 명확히 차단한다.
run_as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "❌ 관리자 권한이 필요하지만 sudo를 찾을 수 없습니다. root로 실행하거나 sudo를 설치하십시오." >&2
    return 1
  fi
}

# Ansible이 사용자를 docker 그룹에 추가해도 현재 로그인 프로세스의 supplementary
# groups는 자동 갱신되지 않는다. 계정 DB에는 docker가 있지만 현재 세션에는 없을 때만
# 재로그인/newgrp 안내를 출력해 fresh install 직후의 권한 오류를 설명한다.
warn_docker_group_refresh() {
  if [ "$(uname -s)" != "Linux" ] || [ "$(id -u)" -eq 0 ]; then
    return 0
  fi

  local user current_groups account_groups
  user="$(id -un)"
  current_groups="$(id -nG)"
  account_groups="$(id -nG "$user" 2>/dev/null || true)"

  if [[ " $account_groups " == *" docker "* ]] && [[ " $current_groups " != *" docker "* ]]; then
    echo "🐳 Docker 그룹 설정은 완료됐지만 현재 로그인 세션에는 아직 반영되지 않았습니다."
    echo "   로그아웃 후 다시 로그인하거나, 현재 셸에서 'newgrp docker'를 실행한 뒤 Docker를 사용하세요."
  fi
}

# RHEL 호환 배포판은 EPEL release 패키지가 기본 dnf 저장소에 없을 수 있다.
# rpm의 %{rhel} 매크로가 숫자로 해석되는 Enterprise Linux 계열에서만, 해당 메이저
# 버전의 Fedora EPEL release RPM을 직접 설치한다. Fedora 등 다른 dnf 계열은 건너뛴다.
install_epel_release() {
  local os_major=""
  os_major="$(rpm -E '%{rhel}' 2>/dev/null || true)"
  case "$os_major" in
  '' | '%{rhel}' | *[!0-9]*)
    return 0
    ;;
  esac
  run_as_root dnf install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${os_major}.noarch.rpm"
}

# sudo 정책과 시스템 대체 실행 파일은 변경하지 않는다.
# Ansible의 sudo 호환성은 run-setup.sh가 해당 실행에만 적용한다.

# 1. OS 패키지 매니저 판별
# stow는 ansible의 packages 역할이 나중에 다시 설치하지만(멱등), mise config.toml을
# ansible보다 먼저 링크해야 해서(아래 3단계) 여기서 미리 확보해둔다.
# gnupg(gpg)는 아래 2단계에서 mise 설치 스크립트의 GPG 서명을 검증하는 데 필요해
# ansible packages 롤(Docker GPG 검증용)보다 먼저 여기서 확보해둔다.
if command -v apt-get &>/dev/null; then
  run_as_root apt-get update -qq
  run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y curl git unzip stow gnupg gawk
elif command -v dnf &>/dev/null; then
  # RHEL/Rocky/Alma/CentOS 등 Enterprise Linux 계열은 stow를 위해 EPEL이 필요할 수 있다.
  # stock RHEL은 bare "epel-release" 패키지가 기본 저장소에 없으므로 direct RPM으로 bootstrap.
  if ! command -v stow &>/dev/null; then
    install_epel_release
  fi
  run_as_root dnf install -y curl git unzip stow gnupg2 gawk
elif command -v brew &>/dev/null; then
  # macOS는 기본 내장 도구 활용, stow/gnupg만 별도 설치
  if ! command -v stow &>/dev/null; then
    brew install stow
  fi
  if ! command -v gpg &>/dev/null; then
    brew install gnupg
  fi
else
  echo "❌ 지원하지 않는 운영체제/패키지 매니저입니다." >&2
  exit 1
fi

# 2. 도구 버전 관리자(mise) 설치
# 공급망 검증(공식 GPG 키로 설치 스크립트 서명 확인)은 bin/utils/install-mise.sh 에 있다.
# CI(.github/workflows/ci.yml verify job)도 같은 스크립트를 부른다 — 예전엔 CI 만
# `curl | sh` 라 같은 저장소가 두 가지 신뢰 수준으로 mise 를 들이고 있었다.
#
# 참고: mise 문서의 "공식 저장소" 설치(apt는 extrepo, dnf는 ppa)는 실측 결과 미채택 —
# apt: Debian 공식 extrepo-data 큐레이션 목록에 mise 항목이 없어 `extrepo enable mise`가
# 실패. dnf: ppa:jdxcode/mise는 Launchpad 기반이라 Ubuntu 전용이라 dnf 계열엔 해당 없음.
# 배포판에 좌우되지 않는 GPG 서명 검증 방식을 모든 OS에 공통 적용한다.
bash "$SCRIPT_DIR/bin/utils/install-mise.sh"

export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"

# 3. 글로벌 도구(Ansible, Just) 설치 (mise 활용)
echo "=> Installing Ansible & Just via mise & pipx..."
# ansible-core와 just는 pipx/직접 설치 패턴 대신, mise 환경(config.toml)에 위임하여 SSOT를 유지합니다.

echo "========================================================="
echo "=> 🚀 Running 'mise install' automatically..."
# PATH 는 바로 위(mise 설치 직후)에서 shims 와 함께 이미 확정했다. 여기서 다시 export
# 하면 진실의 원천이 두 곳이 되고, 앞의 선언이 바뀌어도 이쪽이 조용히 덮어쓴다.
mkdir -p "$HOME/.config/mise"
# mise install이 ansible(및 그 안의 stow 역할)보다 먼저 필요해 GNU Stow로 미리
# 링크해둔다. ansible stow 역할이 나중에 같은 패키지를 다시 stow해도(-R은 멱등) 안전.
# 기존 사용자 파일이 있으면 stow-backup.sh로 먼저 백업한다.
# --no-folding 필수: 위 mkdir -p로 ~/.config/mise를 미리 만들어도 GNU Stow는 그게
# 비어 있으면 여전히 ~/.config 전체를 하나의 심볼릭 링크로 통째 접어버린다(실측
# 재현됨). 그러면 이후 다른 도구(gh, infracost 등)가 ~/.config/<자기이름>/에 쓰는
# 설정이 전부 그 심볼릭 링크를 타고 이 저장소 안으로 흘러들어가 커밋 후보가 되거나
# 저장소 정리 시 유실된다 — 실제로 사고가 난 적이 있다. --no-folding으로 mise가
# 가진 리프 파일만 개별 심볼릭 링크하도록 강제해 ~/.config는 항상 실제 디렉토리로
# 남긴다.
bash "$SCRIPT_DIR/bin/utils/stow-backup.sh" mise "$SCRIPT_DIR/stow" "$HOME"
(cd "$SCRIPT_DIR/stow" && stow -t "$HOME" -R --no-folding mise)
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

chmod +x "$SCRIPT_DIR/stow/git/.githooks/pre-commit" "$SCRIPT_DIR/stow/git/.githooks/commit-msg" "$SCRIPT_DIR/stow/git/.githooks/pre-push" 2>/dev/null || true

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
  (
    umask 077
    cat >"$HOME/.zshrc.local" <<EOF
# 로컬 전용 시크릿 환경 변수 및 오버라이드 설정
# 이 파일은 Git에 커밋되지 않아야 합니다. (.gitignore 규칙 확인)

# export GITHUB_TOKEN="your_token_here"
# export OPENAI_API_KEY="your_api_key_here"
EOF
  )
  echo "✅ ~/.zshrc.local 생성 완료. (이 파일에 필요한 시크릿 값을 추가하세요)"
else
  echo "✅ ~/.zshrc.local 이 이미 존재합니다."
fi

chmod 600 "$HOME/.zshrc.local"

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
bash "$SCRIPT_DIR/.github/scripts/verify-bootstrap-env.sh"
echo "✅ Bootstrap 및 전체 환경 셋업(Ansible & mise)이 성공적으로 완료되었습니다!"
echo "💡 변경된 환경 변수 및 쉘 환경을 적용하려면 'exec zsh' 를 실행하세요."
warn_docker_group_refresh
# ansible docker 롤의 안내 태스크는 다른 롤들 출력에 파묻혀 놓치기 쉬우므로,
# 실제로 눈에 띄는 스크립트 맨 마지막에 한 번 더 띄운다.
if [ "$(uname)" = "Darwin" ]; then
  echo "🐳 macOS는 Docker Engine을 네이티브로 설치할 수 없습니다."
  echo "   https://www.docker.com/products/docker-desktop 에서 Docker Desktop을 직접 설치하거나,"
  echo "   Colima/OrbStack 같은 경량 대안을 사용하십시오."
fi
echo "========================================================="

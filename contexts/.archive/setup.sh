#!/usr/bin/env bash
# 🚀 클라우드 인프라 엔지니어 한 방 세팅 (Troubleshooting 및 AI 브레인 연동 완료 버전)

# 오류 시 중단 (파이프라인 오류 및 미선언 변수 참조 포함)
set -euo pipefail

# 임시 디렉토리 생성 및 스크립트 종료 시(정상/비정상 무관) 자동 정리 (020 룰북 권장)
SETUP_TMPDIR="/tmp/dotfiles-setup-$$"
mkdir -p "$SETUP_TMPDIR"
trap 'rm -rf "$SETUP_TMPDIR"' EXIT

# =============================================================================
# 부트스트랩 이식성 계약: 이 파일은 bash 3.2 에서 실행 가능해야 한다
# =============================================================================
# Apple 은 GPLv3 회피로 /bin/bash 를 3.2.57 에 동결했다. 그런데 bash 4 를 설치하는 것이
# 바로 이 스크립트다. 부트스트랩이 자기가 설치할 물건을 미리 요구하면, 사용자가 손으로
# brew install bash 를 먼저 쳐야 하는 닭-달걀이 된다. 설치 스크립트의 존재 이유와 어긋난다.
#
# 따라서 이 파일에는 bash 4 전용 문법(mapfile/readarray, declare -A, ${v^^}, [[ -v ]],
# local -n 등)을 쓰지 않는다. 검증기와 훅은 이 제약을 받지 않는다. 그것들은 이 스크립트가
# bash 를 설치한 뒤에 실행되고, 셔뱅이 env bash 라 brew 판 최신 bash 를 집는다.
#
# GNU 도구(readlink -f, 인자 없는 mktemp, find -printf)도 같은 이유로 [1/6] 패키지 설치
# 이후에만 사용한다. 그 직후에 gnubin 을 이 프로세스의 PATH 앞에 얹는다.
#
# 이 계약은 문장으로만 두면 나중에 mapfile 한 줄로 조용히 깨지므로,
# contexts/dotfiles/tests/setup-idempotency.sh 가 기계로 검사한다.

# =============================================================================
# 실행 옵션 및 공용 헬퍼
# =============================================================================
# 이 스크립트는 $HOME 에 심볼릭 링크를 걸고 기존 설정 파일을 백업 후 삭제하며 sudo 로
# 시스템 패키지를 설치한다. 실행 전에 "무엇이 바뀌는가"를 확인할 방법이 없어서 처음
# 돌리는 환경에서는 사실상 도박이었다. --dry-run 은 상태를 바꾸는 모든 명령을 실행 대신
# 출력으로 바꾼다. 판별(OS 감지)과 조회는 실제 실행과 동일하게 수행해야 계획이 같은
# 분기를 타므로, 읽기 전용 동작은 dry-run 에서도 그대로 실행한다.
DRY_RUN=false
while [ $# -gt 0 ]; do
  case "$1" in
  --dry-run)
    DRY_RUN=true
    ;;
  -h | --help)
    cat <<'USAGE'
사용법: bash setup.sh [--dry-run]

  --dry-run   상태를 변경하지 않고 실행 계획만 출력합니다.
  -h, --help  이 도움말을 출력합니다.
USAGE
    exit 0
    ;;
  *)
    echo "❌ 에러: 알 수 없는 옵션 '$1' (사용법은 --help 참조)" >&2
    exit 1
    ;;
  esac
  shift
done

# 상태를 바꾸는 단일 명령은 전부 이 함수를 거친다.
run() {
  if [ "$DRY_RUN" = true ]; then
    printf '   [dry-run] %s\n' "$*"
    return 0
  fi
  "$@"
}

# 리다이렉션·힙독·jq 병합처럼 run 으로 감쌀 수 없는 블록용. dry-run 일 때만 0 을 반환하므로
# 호출부는 `if ! plan_only "설명"; then <실제 작업>; fi` 형태로 쓴다.
plan_only() {
  [ "$DRY_RUN" = true ] || return 1
  printf '   [dry-run] %s\n' "$*"
  return 0
}

# 실제로 무언가를 바꿨을 때만 성공을 보고한다. dry-run 에서 "생성 완료"를 출력하면 계획을
# 결과로 오인하게 되므로, 이 경로에서는 아무것도 출력하지 않는다.
ok() {
  [ "$DRY_RUN" = true ] && return 0
  printf '   ✅ %s\n' "$*"
}

# =============================================================================
# 실행 환경 판별 (OS 계열 / 패키지 매니저 / WSL)
# =============================================================================
# 030-toolchain-management-standard.md 의 [MUST] OS Package Manager Compatibility 조항은
# 패키지 매니저를 가정하지 말고 판별하도록 요구하는데, 이 스크립트는 apt 를 하드코딩해
# 데비안 계열이 아닌 환경에서는 [1/6] 단계에서 즉사했다.
#
# 검증 범위: apt(Ubuntu/WSL) 경로만 실제 실행으로 검증되었다. dnf/brew 경로는 구조만
# 맞춘 미검증 경로이므로, 해당 환경에서 처음 실행할 때는 --dry-run 으로 계획을 먼저
# 확인하십시오.
OS_FAMILY=""
PKG_MANAGER=""
IS_WSL=false

detect_platform() {
  case "$(uname -s)" in
  Linux)
    if command -v apt-get &>/dev/null; then
      OS_FAMILY="debian"
      PKG_MANAGER="apt-get"
    elif command -v dnf &>/dev/null; then
      OS_FAMILY="rhel"
      PKG_MANAGER="dnf"
    else
      echo "❌ 에러: 지원하는 패키지 매니저(apt-get, dnf)를 찾을 수 없습니다." >&2
      exit 1
    fi
    if grep -qi microsoft /proc/version 2>/dev/null; then
      IS_WSL=true
    fi
    ;;
  Darwin)
    if ! command -v brew &>/dev/null; then
      echo "❌ 에러: macOS 에서는 Homebrew 가 필요합니다 (https://brew.sh)." >&2
      exit 1
    fi
    OS_FAMILY="macos"
    PKG_MANAGER="brew"
    ;;
  *)
    echo "❌ 에러: 지원하지 않는 OS 입니다: $(uname -s)" >&2
    exit 1
    ;;
  esac
}
detect_platform

echo "=> 감지된 환경: $OS_FAMILY ($PKG_MANAGER)$([ "$IS_WSL" = true ] && echo ", WSL")$([ "$DRY_RUN" = true ] && echo " [DRY-RUN 모드]")"

# 1. 실행 경로 체크 (윈도우 마운트 경로에서 실행 방지)
# /mnt/c 는 WSL 에서만 의미가 있다. 리눅스 서버에도 존재할 수 있는 경로라 무조건 검사하면
# 오탐이 된다.
if [ "$IS_WSL" = true ] && [[ "$(pwd)" == /mnt/c/* ]]; then
  echo "❌ 에러: /mnt/c/ (윈도우 경로)에서 실행 중입니다."
  echo "도트파일은 반드시 리눅스 네이티브 경로(예: ~/dotfiles)에 있어야 합니다."
  exit 1
fi

# 스크립트가 실행된 위치와 무관하게 dotfiles 경로를 안전하게 가져옴
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 패키지 이름은 매니저마다 다르다. 공통 목록을 두고 계열별 차이만 흡수한다.
# ca-certificates/gnupg 는 아래 Docker 저장소 등록(키 지문 대조)의 선행 의존성이다.
pkg_list() {
  case "$OS_FAMILY" in
  debian) printf '%s\n' git curl unzip wget zsh stow pipx python3-venv dnsutils tree ca-certificates gnupg ;;
  # bind-utils=dnsutils. venv 는 python3 에 포함되어 별도 패키지가 없다.
  rhel) printf '%s\n' git curl unzip wget zsh stow pipx python3 bind-utils tree ca-certificates gnupg2 ;;
  # macOS 는 dig 가 기본 제공되고 venv 가 brew python 에 포함되므로 두 항목을 제외한다.
  # 대신 GNU 툴체인을 명시적으로 얹는다. 이 저장소의 검증기들은 mapfile(bash 4+),
  # readlink -f, find -printf, sha256sum, sed -i 처럼 GNU 전용 인터페이스에 의존하는데,
  # BSD 판으로 하나씩 우회하면 검증 로직 자체를 갈라 놓아야 해서 회귀 위험이 커진다.
  # 도구를 맞추는 쪽이 로직을 갈라 놓는 쪽보다 싸다(zsh/.zshenv 가 gnubin 을 PATH 앞에 붙인다).
  macos) printf '%s\n' git curl unzip wget zsh stow pipx tree bash coreutils gnu-sed findutils grep ;;
  esac
}

pkg_missing() {
  case "$PKG_MANAGER" in
  apt-get) ! dpkg -s "$@" >/dev/null 2>&1 ;;
  dnf) ! rpm -q "$@" >/dev/null 2>&1 ;;
  brew) ! brew list --formula "$@" >/dev/null 2>&1 ;;
  esac
}

pkg_install() {
  case "$PKG_MANAGER" in
  apt-get)
    # 030 조항: 설치 중 프롬프트가 뜨면 자동화가 멈추므로 비대화형을 강제한다.
    run sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
    ;;
  dnf) run sudo dnf install -y "$@" ;;
  # brew 는 sudo 로 실행하면 안 된다(권한이 꼬여 이후 brew 명령이 전부 깨진다).
  brew) run brew install "$@" ;;
  esac
}

# =============================================================================
# 모듈화된 설치 단계 (Functional Architecture)
# =============================================================================

step1_install_os_packages() {
  echo "[1/6] 필수 패키지 설치 여부 검증 및 설치 중 (pipx 포함)..."
  # mapfile 을 쓰지 않는 이유는 파일 상단의 부트스트랩 이식성 계약 참조.
  PACKAGES=()
  while IFS= read -r PKG_NAME; do
    PACKAGES+=("$PKG_NAME")
  done < <(pkg_list)
  if pkg_missing "${PACKAGES[@]}"; then
    pkg_install "${PACKAGES[@]}"
  fi

  # macOS 한정: 방금 설치한 GNU 도구를 이 스크립트 자신의 PATH 앞에도 얹는다.
  # zsh/.zshenv 가 같은 일을 하지만 그것은 "앞으로 열리는 셸"에만 적용된다. 지금 돌고 있는
  # 이 프로세스는 여전히 BSD 도구를 보고 있어서, 아래에서 쓰는 mktemp(BSD 는 템플릿 인자가
  # 필수라 인자 없는 호출이 실패)와 readlink -f(BSD 에 -f 없음)가 그대로 깨진다.
  # 첫 실행에서 실제로 걸리는 지점이라 여기서 자급자족해야 한다.
  if [ "$OS_FAMILY" = "macos" ]; then
    for BREW_PREFIX in /opt/homebrew /usr/local; do
      [ -d "$BREW_PREFIX/opt" ] || continue
      for GNU_PKG in coreutils gnu-sed findutils grep; do
        if [ -d "$BREW_PREFIX/opt/$GNU_PKG/libexec/gnubin" ]; then
          PATH="$BREW_PREFIX/opt/$GNU_PKG/libexec/gnubin:$PATH"
        fi
      done
      break
    done
    export PATH
  fi

  # -----------------------------------------------------------------------------
  # Docker 설치 및 사용자 권한 설정
  # -----------------------------------------------------------------------------
  # 이전 구현은 `curl -fsSL https://get.docker.com | sudo sh` 였다. 원격 스크립트를 아무런
  # 검증 없이 root 로 실행하는 형태여서, 이 저장소가 공급망 보안(cosign, trivy, syft)을
  # 강제하는 룰북을 갖고 있다는 사실과 정면으로 충돌했다. Docker 공식 문서가 프로덕션에
  # 권장하는 저장소 등록 방식으로 바꾸고, 배포 키의 지문을 상수로 고정해 대조한다.
  # TLS 만 믿는 것과 달리 키가 바뀌면 설치가 중단된다.
  DOCKER_GPG_FINGERPRINT="9DC858229FC7DD38854AE2D88D81803C0EBFCD88"

  # /etc/os-release 를 현재 셸에 그대로 source 하면 NAME, VERSION 등 20여 개 변수가 전역으로
  # 흘러든다. 서브셸에서 읽어 필요한 키 하나만 꺼낸다.
  os_release_value() {
    local key=$1
    # /etc/os-release 는 런타임에만 존재하는 시스템 파일이라 정적 분석 대상이 아니다.
    # shellcheck source=/dev/null
    (. /etc/os-release && printf '%s\n' "${!key:-}")
  }

  install_docker_debian() {
    local keyring="/etc/apt/keyrings/docker.asc"
    local repo_os codename arch tmp_key fingerprint
    repo_os=$(os_release_value ID)
    # Ubuntu 파생 배포판(Mint 등)은 ID 가 달라도 Ubuntu 저장소와 그 코드네임을 써야 한다.
    codename=$(os_release_value UBUNTU_CODENAME)
    if [ -n "$codename" ]; then
      repo_os="ubuntu"
    else
      codename=$(os_release_value VERSION_CODENAME)
      [ "$repo_os" = "ubuntu" ] || repo_os="debian"
    fi

    if [ "$DRY_RUN" = true ]; then
      printf '   [dry-run] Docker 공식 저장소(%s %s) 등록 및 키 지문 대조 후 docker-ce 설치\n' "$repo_os" "$codename"
      return 0
    fi

    arch=$(dpkg --print-architecture)
    sudo install -m 0755 -d /etc/apt/keyrings
    tmp_key="$SETUP_TMPDIR/docker.asc"
    if ! curl -fsSL "https://download.docker.com/linux/$repo_os/gpg" -o "$tmp_key"; then
      rm -f "$tmp_key"
      echo "❌ 에러: Docker GPG 키 다운로드에 실패했습니다 (네트워크 확인 필요)." >&2
      return 1
    fi
    fingerprint=$(gpg --show-keys --with-colons "$tmp_key" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')
    if [ "$fingerprint" != "$DOCKER_GPG_FINGERPRINT" ]; then
      rm -f "$tmp_key"
      echo "❌ 에러: Docker GPG 키 지문이 일치하지 않아 설치를 중단합니다." >&2
      echo "   기대: $DOCKER_GPG_FINGERPRINT / 실제: ${fingerprint:-확인 불가}" >&2
      return 1
    fi
    sudo install -m 0644 "$tmp_key" "$keyring"
    rm -f "$tmp_key"
    echo "deb [arch=$arch signed-by=$keyring] https://download.docker.com/linux/$repo_os $codename stable" |
      sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
      docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  }

  install_docker_rhel() {
    local repo_os repo_url dnf_version dnf_major
    # RHEL/Rocky/Alma 는 CentOS 저장소를 공유한다. Fedora 만 자체 저장소를 쓴다.
    repo_os=$(os_release_value ID)
    [ "$repo_os" = "fedora" ] || repo_os="centos"
    repo_url="https://download.docker.com/linux/$repo_os/docker-ce.repo"

    # Fedora 41+ 의 dnf5 는 `config-manager --add-repo` 를 없애고 `addrepo --from-repofile` 로
    # 바꿨다. 버전을 판별하지 않으면 최신 Fedora 에서 저장소 등록이 통째로 실패한다.
    # 파이프(`dnf --version | head -1`)를 쓰지 않는다: head 의 조기 종료가 보내는 SIGPIPE 가
    # pipefail 아래에서 명령 실패로 뒤집혀 set -e 에 걸린다. 버전 문자열이 출력 맨 앞에 오므로
    # 첫 '.' 앞을 잘라내는 것으로 충분하다.
    dnf_version=$(dnf --version 2>/dev/null || true)
    dnf_major=${dnf_version%%.*}
    [[ "$dnf_major" =~ ^[0-9]+$ ]] || dnf_major=4

    if [ "$DRY_RUN" = true ]; then
      printf '   [dry-run] Docker 공식 저장소(%s) 등록 후 docker-ce 설치 (dnf%s 문법)\n' "$repo_os" "$dnf_major"
      return 0
    fi

    if [ "$dnf_major" -ge 5 ]; then
      sudo dnf install -y dnf5-plugins
      sudo dnf config-manager addrepo --from-repofile="$repo_url"
    else
      sudo dnf install -y dnf-plugins-core
      sudo dnf config-manager --add-repo "$repo_url"
    fi
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  }

  if ! command -v docker &>/dev/null; then
    echo "=> Docker Engine(docker-ce)을 공식 저장소에서 설치합니다..."
    case "$OS_FAMILY" in
    debian) install_docker_debian ;;
    rhel) install_docker_rhel ;;
    macos)
      # Docker Desktop 은 GUI 앱이고 조직 규모에 따라 유료 라이선스 대상이라 무단 설치하지 않는다.
      echo "   ⚠️ macOS 는 Docker Desktop 을 직접 설치하십시오: https://docs.docker.com/desktop/setup/install/mac-install/"
      ;;
    esac
  fi

  # systemctl 이 없는 환경(macOS, 컨테이너)에서는 서비스 등록 단계 자체가 성립하지 않는다.
  # 판정에 파이프를 쓰지 않는다: `systemctl ... | grep -q` 형태는 grep 이 조기 종료하며 보내는
  # SIGPIPE 가 pipefail 아래에서 파이프라인 실패로 뒤집혀, 조건이 조용히 거짓이 된다.
  if command -v systemctl &>/dev/null && [ -n "$(systemctl list-unit-files --no-legend docker.service 2>/dev/null)" ]; then
    run sudo systemctl enable --now docker
    if ! groups "$USER" | grep -qw "docker"; then
      echo "=> 현재 사용자를 docker 그룹에 추가합니다..."
      run sudo usermod -aG docker "$USER"
      echo "💡 안내: Docker 그룹 권한이 부여되었습니다. 적용을 위해 터미널 재시작 또는 'newgrp docker'가 필요합니다."
    fi
  fi

}

step2_setup_zsh_and_plugins() {
  echo "[2/6] Oh My Zsh 및 플러그인 구성 중..."
  if [ ! -d "$HOME/.oh-my-zsh" ] && ! plan_only "Oh My Zsh 설치 (unattended)"; then
    # sh -c "$(curl ...)" 형태는 curl이 네트워크 오류로 실패해도 sh -c ""(빈 명령)가 성공으로
    # 처리되어 set -e가 실패를 감지하지 못한다. 다운로드를 별도 임시 파일로 받아 curl의
    # 종료 코드를 직접 검사해야 네트워크 타임아웃 같은 실패를 확실히 잡아낼 수 있다.
    OMZ_INSTALLER="$SETUP_TMPDIR/omz_install.sh"
    if ! curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$OMZ_INSTALLER"; then
      echo "❌ 에러: Oh My Zsh 설치 스크립트 다운로드에 실패했습니다 (네트워크 확인 필요)." >&2
      exit 1
    fi
    sh "$OMZ_INSTALLER" "" --unattended
    rm -f "$OMZ_INSTALLER"
  fi

  ZSH_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}
  [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] && run git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
  [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] && run git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

  # dry-run 은 패키지 설치를 출력으로만 대체하므로, zsh 가 아직 없는 신규 환경에서는 이 조회가
  # 실패한다. set -e 아래에서 명령 치환 대입 실패는 아무 메시지도 남기지 않고 스크립트를 죽이므로,
  # "처음 돌리는 환경에서 계획을 먼저 본다"는 dry-run 의 목적이 정확히 그 환경에서만 무너졌다.
  ZSH_BIN=$(command -v zsh || true)
  if [ -z "$ZSH_BIN" ]; then
    echo "   ⏭️ zsh 가 아직 설치되지 않아 기본 셸 변경을 건너뜁니다."
  elif [ "$SHELL" != "$ZSH_BIN" ]; then
    # chsh 는 대상 셸이 /etc/shells 에 등록되어 있어야만 성공한다. 배포판 기본 zsh 는 이미
    # 등록되어 있지만 brew 로 설치한 zsh(/opt/homebrew/bin/zsh)는 그렇지 않아 여기서 막힌다.
    if ! grep -qxF "$ZSH_BIN" /etc/shells 2>/dev/null; then
      run sudo sh -c "echo '$ZSH_BIN' >> /etc/shells"
    fi
    run sudo chsh -s "$ZSH_BIN" "$USER"
  fi

}

step3_setup_stow_symlinks() {
  echo "[3/6] Stow 연결을 위한 기존 파일 정리 및 연결..."
  # 아래 패키지 스캔(for d in */)은 CWD 기준으로 동작하므로, 다른 디렉토리에서
  # `bash ~/dotfiles/setup.sh`로 호출하면 엉뚱한 폴더가 stow 패키지로 잡혀 실패한다.
  # 15행에서 선언한 "실행 위치 무관" 계약을 지키기 위해 스캔 전에 저장소 루트로 이동한다.
  cd "$DOTFILES_DIR"

  # stow 대상 부모 디렉토리 선생성 (mise 설정이 ~/.config/mise/ 하위로 이동함)
  # ~/.config/mise 까지 미리 만드는 이유: 이 디렉토리가 없으면 stow 가 트리 폴딩으로
  # ~/.config/mise 자체를 저장소로 향하는 심볼릭 링크로 만들어 버린다. 그러면 로컬 전용
  # 오버라이드(~/.config/mise/conf.d/*.toml)를 두는 순간 추적 대상 저장소에 파일이 생긴다.
  run mkdir -p "$HOME/.config/mise"

  # 구버전 배치에서 만들어진 ~/.mise.toml 링크는 더 이상 패키지에 없어 stow -R이 걷어내지
  # 못하므로, dotfiles를 가리키는 경우에 한해 직접 정리한다(사용자 실파일은 건드리지 않음).
  if [ -L "$HOME/.mise.toml" ] && [[ "$(readlink -f "$HOME/.mise.toml")" == "$DOTFILES_DIR"/* || ! -e "$HOME/.mise.toml" ]]; then
    run rm -f "$HOME/.mise.toml"
    echo "   🧹 구 mise 설정 링크(~/.mise.toml)를 제거했습니다. 전역 설정은 ~/.config/mise/config.toml 입니다."
  fi

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
        # 백업 파일명에 시분초까지 넣는다. 예전에는 날짜(%F)만 써서, 같은 날 이미 백업이 있는
        # 상태로 재실행하면 cp -n 이 "이미 있음"으로 조용히 건너뛰고(종료 코드 0) 그 직후 rm 이
        # 원본을 지웠다. 그날 새로 만든 사용자 실파일이 백업 없이 사라지는 경로였다.
        BACKUP_FILE="$TARGET.backup.$(date +%F-%H%M%S)"
        if plan_only "$TARGET → $BACKUP_FILE 백업 후 제거 (stow 링크로 교체 대상)"; then
          continue
        fi
        mkdir -p "$(dirname "$TARGET")"
        # 백업에 실패하면 원본을 남긴다. 지우면 복구 수단이 사라지고, stow 충돌은 그 자리에서
        # 눈에 보이는 실패로 끝나지만 원본 소실은 되돌릴 수 없다.
        if ! cp "$TARGET" "$BACKUP_FILE"; then
          echo "   ⚠️ 백업 실패로 $TARGET 을 그대로 둡니다 (이 파일에서 stow 충돌이 발생할 수 있습니다)." >&2
          continue
        fi
        rm -f "$TARGET"
      fi
    done < <(find "$DOTFILES_DIR/$PKG" -type f -print0)
  done

  cd "$DOTFILES_DIR"
  run stow -t "$HOME" -R "${STOW_PKGS[@]}"

}

step4_install_mise_and_tools() {
  echo "[4/6] 도구 버전 관리자(mise) 설치 및 인프라 도구 일괄 설치..."
  if ! command -v ~/.local/bin/mise &>/dev/null && ! plan_only "mise 설치 (https://mise.run)"; then
    # -fsSL: HTTP 오류(5xx 등) 시 curl이 오류 페이지를 sh로 흘리지 않고 실패하도록 강제
    # (set -o pipefail이 이 실패를 감지해 중단시킨다)
    curl -fsSL https://mise.run | sh
  fi

  # Ansible 등을 위한 pipx 환경 반영
  export PATH="$HOME/.local/bin:$PATH"

  # Mise 환경 신뢰 설정 및 도구 일괄 설치 (절대 경로 호출로 안정성 확보)
  # 설정은 ~/.config/mise/config.toml(전역)에 둔다. ~/.mise.toml은 전역 설정이 아니라
  # "$HOME 디렉토리에만 적용되는 로컬 설정"이라, $HOME 밖 저장소(/tmp, /srv, /mnt/c 등)에서는
  # 도구가 해석되지 않아 pre-flight-check.sh의 has_tool()이 전 항목을 건너뛰고도
  # "All Checks Passed"를 출력하는 무검증 통과 사고로 이어졌다(2026-07-26 실측).
  run ~/.local/bin/mise trust "$HOME/.config/mise/config.toml" || true
  run ~/.local/bin/mise install -y
  run ~/.local/bin/mise ls

  export PATH="$HOME/.local/share/mise/shims:$PATH"
  if command -v tflint &>/dev/null && command -v jq &>/dev/null; then
    if ! plan_only "tflint 플러그인(AWS, Azure, GCP) 최신 버전 갱신 및 초기화"; then
      TFLINT_HCL="$DOTFILES_DIR/tflint/.tflint.hcl"
      mkdir -p "$(dirname "$TFLINT_HCL")"

      if [ ! -f "$TFLINT_HCL" ]; then
        echo "   => GitHub API에서 tflint 플러그인 최신 릴리즈 조회 중..."
        AWS_LATEST=$(curl -sS https://api.github.com/repos/terraform-linters/tflint-ruleset-aws/releases/latest 2>/dev/null | jq -r '.tag_name' | sed 's/^v//' || true)
        AZURE_LATEST=$(curl -sS https://api.github.com/repos/terraform-linters/tflint-ruleset-azurerm/releases/latest 2>/dev/null | jq -r '.tag_name' | sed 's/^v//' || true)
        GCP_LATEST=$(curl -sS https://api.github.com/repos/terraform-linters/tflint-ruleset-google/releases/latest 2>/dev/null | jq -r '.tag_name' | sed 's/^v//' || true)

        if [ -n "$AWS_LATEST" ] && [ "$AWS_LATEST" != "null" ] && [ -n "$AZURE_LATEST" ] && [ "$AZURE_LATEST" != "null" ] && [ -n "$GCP_LATEST" ] && [ "$GCP_LATEST" != "null" ]; then
          echo "[+] tflint 글로벌 플러그인 초기화 중... (AWS: $AWS_LATEST, Azure: $AZURE_LATEST, GCP: $GCP_LATEST)"
          cat <<EOF >"$TFLINT_HCL"
plugin "aws" {
  enabled = true
  version = "${AWS_LATEST}"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

plugin "azurerm" {
  enabled = true
  version = "${AZURE_LATEST}"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

plugin "google" {
  enabled = true
  version = "${GCP_LATEST}"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}
EOF
          echo "   ✅ .tflint.hcl 플러그인 버전을 최신(AWS: ${AWS_LATEST}, Azure: ${AZURE_LATEST}, GCP: ${GCP_LATEST})으로 생성했습니다."
        else
          echo "   ⚠️ GitHub API 연동 실패로 기본 tflint 플러그인 구성을 생성하지 못했습니다."
        fi
      fi
      run tflint --init || echo "tflint --init 실패"
    fi
  else
    echo "   ⏭️ tflint나 jq가 아직 설치되지 않아 초기화를 건너뜁니다."
  fi

  echo "[+] Helm 플러그인 설치 중 (helm-diff)..."
  export PATH="$HOME/.local/share/mise/shims:$PATH"
  # helm 자체가 위 mise install 로 들어오므로, dry-run 이나 설치 실패 시에는 존재하지 않는다.
  if ! command -v helm &>/dev/null; then
    echo "   ⏭️ helm 이 아직 설치되지 않아 플러그인 구성을 건너뜁니다."
  # 판정에 파이프를 쓰지 않는다. grep -q 의 조기 종료가 보내는 SIGPIPE 가 pipefail 아래에서
  # 파이프라인 실패로 뒤집혀, 플러그인이 이미 있어도 재설치를 시도할 수 있다(3055e5b 동일 유형).
  elif ! grep -q "^diff" <<<"$(helm plugin list 2>/dev/null || true)"; then
    run helm plugin install https://github.com/databus23/helm-diff --verify=false || echo "helm-diff 플러그인 설치 실패"
  else
    echo "helm-diff 플러그인이 이미 설치되어 있습니다."
  fi

}

step5_deploy_agent_rules() {
  echo "[5/6] 사용자 워크스페이스 생성 및 제미나이/클로드 AI 글로벌 룰셋 등록 중..."

  CONTEXTS_DIR="$DOTFILES_DIR/contexts"

  # jq 는 apt/brew 패키지 목록이 아니라 mise 로 들어오므로([4/6] 단계), 그 단계가 실패하면 이
  # 시점에 없을 수 있다. 없는 상태에서 `jq empty` 를 호출하면 127 로 실패하는데, 아래 두 블록의
  # else 분기는 그것을 "파일이 유효한 JSON 이 아니다"로 보고해 엉뚱한 곳을 고치게 만든다.
  HAS_JQ=true
  command -v jq &>/dev/null || HAS_JQ=false

  # 사용자 실제 작업용 기본 워크스페이스 폴더 생성
  run mkdir -p "$HOME/workspace"
  ok "기본 워크스페이스 생성 완료: ~/workspace"

  # 제미나이 글로벌 AI 룰셋 링크 주입 (자동 감지용 skills 폴더 포함)
  echo "=> [Gemini Rules] 제미나이 글로벌 AGENTS.md 링크 주입 중..."
  run mkdir -p "$HOME/.gemini/config/skills"
  run ln -sfn "$CONTEXTS_DIR/base.AGENTS.md" "$HOME/.gemini/config/AGENTS.md"
  ok "제미나이 글로벌 룰 세팅 완료: ~/.gemini/config/AGENTS.md"

  run ln -sfn "$CONTEXTS_DIR/.base.aiexclude" "$HOME/.gemini/config/.aiexclude"
  ok "제미나이 글로벌 AI 제외 목록(aiexclude) 세팅 완료: ~/.gemini/config/.aiexclude"

  # 제미나이/Antigravity 훅 등록 (편집 이력 자동 기록)
  # hooks.json의 command는 절대 경로만 허용되어 사용자 홈 경로에 종속되므로, 심볼릭 링크 대신
  # 템플릿의 __HOOK_SCRIPT__를 실제 경로로 치환해 생성한다. 사용자가 /hooks로 추가한 다른 훅을
  # 보존하기 위해 덮어쓰기 대신 훅 이름 기준으로 병합한다.
  HOOK_SCRIPT="$CONTEXTS_DIR/scripts/agent-edits-hook.sh"
  GEMINI_HOOKS="$HOME/.gemini/config/hooks.json"
  # JSON 병합은 파일을 직접 쓰므로 dry-run 에서는 블록 전체를 건너뛴다.
  if ! plan_only "$GEMINI_HOOKS 에 편집 이력 훅(agent-edits-log) 병합"; then
    [ -f "$GEMINI_HOOKS" ] || echo '{}' >"$GEMINI_HOOKS"
    if jq empty "$GEMINI_HOOKS" 2>/dev/null; then
      GEMINI_HOOKS_TMP="$SETUP_TMPDIR/gemini_hooks.json"
      jq -s --arg cmd "$HOOK_SCRIPT" \
        '.[0] * (.[1] | .["agent-edits-log"].PostToolUse[0].hooks[0].command = $cmd)' \
        "$GEMINI_HOOKS" "$CONTEXTS_DIR/base.hooks.json" >"$GEMINI_HOOKS_TMP"
      mv "$GEMINI_HOOKS_TMP" "$GEMINI_HOOKS"
      ok "제미나이 편집 이력 훅 등록 완료: $GEMINI_HOOKS"
    elif [ "$HAS_JQ" = false ]; then
      echo "   ⚠️ jq를 찾을 수 없어 훅 등록을 건너뜁니다. 'mise install -y'로 설치한 뒤 setup.sh를 다시 실행하세요."
    else
      echo "   ⚠️ $GEMINI_HOOKS 파일이 유효한 JSON이 아니어서 훅 등록을 건너뜁니다. 파일을 직접 수정한 뒤 setup.sh를 다시 실행하세요."
    fi
  fi

  # Claude Code 글로벌 설정 추가 (CLAUDE.md 및 skills 디렉토리)
  echo "=> [Claude Code Rules] 클로드 글로벌 CLAUDE.md 링크 주입 중..."
  run mkdir -p "$HOME/.claude/skills"
  run ln -sfn "$CONTEXTS_DIR/base.AGENTS.md" "$HOME/.claude/CLAUDE.md"
  ok "클로드 글로벌 룰 세팅 완료: ~/.claude/CLAUDE.md"

  # 클로드 커밋/PR 어트리뷰션 비활성화 (Co-Authored-By: Claude 트레일러 및 PR 푸터 제거)
  # 사용자가 이미 설정해둔 다른 값(effortLevel 등)을 보존하기 위해 덮어쓰기 대신 jq로 병합한다
  CLAUDE_SETTINGS="$HOME/.claude/settings.json"
  if ! plan_only "$CLAUDE_SETTINGS 에 어트리뷰션 비활성화 및 편집 이력 훅 병합"; then
    [ -f "$CLAUDE_SETTINGS" ] || echo '{}' >"$CLAUDE_SETTINGS"
    if jq empty "$CLAUDE_SETTINGS" 2>/dev/null; then
      CLAUDE_SETTINGS_TMP="$SETUP_TMPDIR/claude_settings.json"
      # 어트리뷰션 비활성화와 편집 이력 훅 등록을 함께 반영한다. 훅은 같은 command를 가진 기존
      # 항목을 먼저 제거한 뒤 추가하므로, setup.sh를 여러 번 실행해도 중복 등록되지 않는다.
      jq --arg cmd "$HOOK_SCRIPT" '
      .attribution.commit = "" | .attribution.pr = ""
      | .hooks.PostToolUse = (
          ((.hooks.PostToolUse // []) | map(select(((.hooks // []) | map(.command) | index($cmd)) == null)))
          + [{matcher: "Edit|Write|MultiEdit|NotebookEdit", hooks: [{type: "command", command: $cmd}]}]
        )
    ' "$CLAUDE_SETTINGS" >"$CLAUDE_SETTINGS_TMP"
      mv "$CLAUDE_SETTINGS_TMP" "$CLAUDE_SETTINGS"
      ok "클로드 어트리뷰션 비활성화 및 편집 이력 훅 등록 완료: $CLAUDE_SETTINGS"
    elif [ "$HAS_JQ" = false ]; then
      echo "   ⚠️ jq를 찾을 수 없어 어트리뷰션 설정과 훅 등록을 건너뜁니다. 'mise install -y'로 설치한 뒤 setup.sh를 다시 실행하세요."
    else
      echo "   ⚠️ $CLAUDE_SETTINGS 파일이 유효한 JSON이 아니어서 어트리뷰션 설정을 건너뜁니다. 파일을 직접 수정한 뒤 setup.sh를 다시 실행하세요."
    fi
  fi

  # 전역 에이전트 스크립트들을 ~/.local/bin/ 에 심볼릭 링크로 꽂아 넣기 (PATH 주입)
  echo "=> [AI Global Scripts] 에이전트 실행 스크립트들을 ~/.local/bin/ 경로에 심볼릭 링크 주입 중..."
  run mkdir -p "$HOME/.local/bin"

  # Bash 4 의 declare -A 없이 POSIX 호환으로 이름 충돌(Naming Collision)을 검사한다.
  if ! find "$CONTEXTS_DIR" -type f -executable -path "*/scripts/*" 2>/dev/null | awk -F/ '
  {
      name = $NF
      if (seen[name] != "") {
          print "   ❌ [FATAL] 스크립트 이름 충돌 감지! '" name "' 파일이 여러 곳에 존재합니다:" > "/dev/stderr"
          print "      1. " seen[name] > "/dev/stderr"
          print "      2. " $0 > "/dev/stderr"
          err = 1
      }
      seen[name] = $0
  }
  END { exit err }
  '; then
    echo "   ❌ 에이전트 스크립트 이름은 글로벌하게 고유해야 합니다(예: k8s-check.sh). 중복을 해결한 뒤 다시 시도해 주세요." >&2
    exit 1
  fi

  while IFS= read -r script_path; do
    [ -n "$script_path" ] || continue
    script_name=$(basename "$script_path")
    run ln -sfn "$script_path" "$HOME/.local/bin/$script_name"
  done < <(find "$CONTEXTS_DIR" -type f -executable -path "*/scripts/*" 2>/dev/null)
  ok "모든 에이전트 스크립트 PATH 주입 완료 (~/.local/bin/)"

  # 모든 컨텍스트 디렉토리 스캔 및 각 AI 에이전트 글로벌 스킬 등록
  echo "=> [AI Global Rules] 각 AI 에이전트 글로벌 스킬 등록 중..."
  for TARGET_DIR in "$CONTEXTS_DIR"/*/; do
    [ -d "$TARGET_DIR" ] || continue
    # 글롭의 트레일링 슬래시를 여기서 한 번 걷어낸다. 그대로 두면 아래 모든 경로 조립이
    # contexts/k8s//SKILL.md 처럼 이중 슬래시로 출력되어 로그를 읽기 어렵게 만든다.
    TARGET_DIR="${TARGET_DIR%/}"
    ENV_NAME="$(basename "$TARGET_DIR")"

    # dotfiles 컨텍스트는 글로벌 등록에서 제외 (글로벌 룰 오염 방지)
    if [ "$ENV_NAME" = "dotfiles" ]; then
      continue
    fi

    # agent-handoff 는 역할별 지침을 배포 시점에 결합해야 하므로 심볼릭 링크 대신 생성한다.
    # 링크로 배포하면 두 에이전트가 같은 파일을 보게 되어 역할 분기가 성립하지 않는다.
    # 공통부(SKILL.md)에 역할 파일 한 벌만 이어 붙여 상대 역할 지침이 배포본에 아예
    # 존재하지 않게 만든다. 한 파일에 두 역할을 담고 "읽지 마십시오" 지시문으로만 차단하면
    # 상대 지침이 그대로 컨텍스트에 적재된다.
    if [ "$ENV_NAME" = "agent-handoff" ]; then
      # 배포 명령의 정본은 scripts/deploy.sh 다. pre-commit 훅의 드리프트 자가 치유도 같은
      # 스크립트를 호출하므로, 여기에 명령을 복제하면 두 경로가 갈린다.
      # 실패해도 exit 하지 않는다. agent-handoff 는 스킬 루프의 첫 항목이라 여기서 죽으면
      # 나머지 스킬이 전부 미등록으로 남는다(2026-07-27 실측).
      run bash "$TARGET_DIR/scripts/deploy.sh" ||
        echo "   ❌ agent-handoff 배포 건너뜀 (위 오류 참조)" >&2
      continue
    fi

    if [ -f "$TARGET_DIR/SKILL.md" ]; then
      # 1. 제미나이 (Gemini) 글로벌 스킬 등록 (자동 감지 디렉토리 연동 - 실시간 심볼릭 링크 구조)
      run mkdir -p "$HOME/.gemini/config/skills/${ENV_NAME}"
      run rm -f "$HOME/.gemini/config/skills/${ENV_NAME}/SKILL.md"
      run ln -sfn "$TARGET_DIR/SKILL.md" "$HOME/.gemini/config/skills/${ENV_NAME}/SKILL.md"
      if [ -d "$TARGET_DIR/references" ]; then
        run ln -sfn "$TARGET_DIR/references" "$HOME/.gemini/config/skills/${ENV_NAME}/references"
      fi
      if [ -d "$TARGET_DIR/scripts" ]; then
        run ln -sfn "$TARGET_DIR/scripts" "$HOME/.gemini/config/skills/${ENV_NAME}/scripts"
      fi
      ok "제미나이 글로벌 스킬 등록 완료 (자동 감지): ~/.gemini/config/skills/${ENV_NAME}/"

      # 2. 클로드 (Claude Code) 글로벌 스킬 등록 (skills 자동 감지 디렉토리 연동 - 온디맨드 로드)
      run mkdir -p "$HOME/.claude/skills/${ENV_NAME}"
      run rm -f "$HOME/.claude/skills/${ENV_NAME}/SKILL.md"
      run ln -sfn "$TARGET_DIR/SKILL.md" "$HOME/.claude/skills/${ENV_NAME}/SKILL.md"
      if [ -d "$TARGET_DIR/references" ]; then
        run ln -sfn "$TARGET_DIR/references" "$HOME/.claude/skills/${ENV_NAME}/references"
      fi
      if [ -d "$TARGET_DIR/scripts" ]; then
        run ln -sfn "$TARGET_DIR/scripts" "$HOME/.claude/skills/${ENV_NAME}/scripts"
      fi
      ok "클로드 글로벌 스킬 등록 완료 (온디맨드): ~/.claude/skills/${ENV_NAME}/"
    fi
  done

  # 저장소에서 사라진 스킬의 배포본을 회수한다. 위 루프는 등록만 하므로, 스킬을 지워도
  # 글로벌 링크가 남아 에이전트가 삭제된 룰을 계속 로드했다(재실행해도 선언한 상태로 수렴하지
  # 않는 상태). 이 저장소가 배포한 것만 대상으로 삼는다: SKILL.md 가 contexts/ 를 가리키는
  # 심볼릭 링크인 항목. 사용자가 직접 만든 스킬이나 다른 도구가 넣은 디렉토리는 그 조건에
  # 걸리지 않아 보존된다. agent-handoff 는 링크가 아니라 역할 결합 복사본이라 이 규칙으로
  # 식별되지 않는데, 사용자 스킬과 구분할 방법이 없으므로 의도적으로 회수 대상에서 뺀다.
  prune_orphan_skills() {
    local skills_root=$1 skill_dir name link_target
    [ -d "$skills_root" ] || return 0
    for skill_dir in "$skills_root"/*/; do
      [ -d "$skill_dir" ] || continue
      skill_dir="${skill_dir%/}"
      name="$(basename "$skill_dir")"
      [ -d "$CONTEXTS_DIR/$name" ] && continue
      link_target="$(readlink "$skill_dir/SKILL.md" 2>/dev/null || true)"
      case "$link_target" in
      "$CONTEXTS_DIR"/*) ;;
      *) continue ;;
      esac
      run rm -rf "$skill_dir"
      ok "저장소에서 제거된 스킬의 배포본 회수: $skill_dir"
    done
  }
  prune_orphan_skills "$HOME/.gemini/config/skills"
  prune_orphan_skills "$HOME/.claude/skills"

  echo "=> [AI Local Rules] 워크스페이스 전용 로컬 규칙 링크 구성 중..."
  # 로컬 루트 폴더 간결화 및 에이전트별 상시 자동 로드 100% 보장
  # 제미나이용 AGENTS.md와 클로드용 CLAUDE.md 링크 파일 2개만 단독 생성 (.agents 폴더 완전 배제)
  run ln -sfn "$DOTFILES_DIR/contexts/dotfiles/SKILL.md" "$DOTFILES_DIR/AGENTS.md"
  ok "제미나이 로컬 규칙 연동 완료: $DOTFILES_DIR/AGENTS.md"
  run ln -sfn "$DOTFILES_DIR/contexts/dotfiles/SKILL.md" "$DOTFILES_DIR/CLAUDE.md"
  ok "클로드 로컬 규칙 연동 완료: $DOTFILES_DIR/CLAUDE.md"

}

step6_security_and_interactive_setup() {
  echo "[6/6] 시크릿 유출 스캔 및 보안 훅(Hook) 구성..."
  if command -v trufflehog &>/dev/null; then
    echo "=> 로컬 dotfiles 디렉토리 시크릿 검증 중..."
    # --fail이 없으면 trufflehog는 시크릿을 찾아도 종료 코드 0으로 끝나 아래 || 분기가
    # 도달 불가능한 데드 코드가 되고, 스캔이 결과와 무관하게 항상 통과한다(2026-07-27 실측).
    # git/.githooks/pre-commit 및 pre-flight-check.sh의 trufflehog 호출과 동일하게 --fail을 붙인다.
    trufflehog git "file://$DOTFILES_DIR" --no-update --fail || {
      echo "❌ [Hard Block] 시크릿 유출 의심 내역이 발견되어 즉시 작업을 중단합니다." >&2
      echo "   유출된 자격 증명을 즉시 파기(Revoke)한 후 Git 히스토리에서 완전히 정리하십시오." >&2
      exit 1
    }
  else
    echo "⚠️ trufflehog를 찾을 수 없어 스캔을 건너뜁니다."
  fi

  # Git 훅 구성 (dotfiles/git/.githooks가 Stow에 의해 ~/.githooks로 연동됨)
  # 실행 권한 부여 (Stow로 이미 심볼릭 링크가 생성되었거나 생성될 예정이므로 원본에 권한 부여)
  run chmod +x "$DOTFILES_DIR/git/.githooks/pre-commit" "$DOTFILES_DIR/git/.githooks/commit-msg"

  # 4. 훅 경로는 추적 파일 git/.gitconfig의 [core] hooksPath에 이미 선언되어 있으므로
  # `git config --global`로 다시 쓰지 않는다. ~/.gitconfig가 그 추적 파일의 심볼릭 링크라
  # --global 쓰기는 저장소 파일을 직접 수정하는 셈이어서, 습관화되면 개인정보까지 추적
  # 대상에 섞여 들어갈 수 있다. 여기서는 연동 결과만 확인해 보고한다.
  HOOKS_PATH=$(git config --global --get core.hooksPath || true)
  if [ -n "$HOOKS_PATH" ]; then
    echo "   ✅ Git 글로벌 훅 경로 확인 완료: $HOOKS_PATH"
  else
    echo "   ⚠️ core.hooksPath가 비어 있습니다. git/.gitconfig가 ~/.gitconfig로 링크되었는지 확인하세요."
  fi

  echo "========================================================="
  echo "🎉 모든 기본 설치 및 환경 세팅이 백그라운드로 완료되었습니다!"
  echo "마지막으로 사용자 맞춤 설정(선택)을 진행합니다."
  echo "========================================================="

  # 로컬 Git 설정
  echo -e "\n[선택] Git 로컬 사용자 설정"
  if [ ! -f ~/.gitconfig.local ]; then
    if plan_only "$HOME/.gitconfig.local 대화형 생성 (Git 이름/이메일 입력)"; then
      : # dry-run 에서는 입력 프롬프트를 띄우지 않는다
    elif [ -t 0 ]; then
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
  if [ -f ~/.zshrc.local ]; then
    echo "✅ 이미 ~/.zshrc.local 파일이 존재하여 설정을 건너뜁니다."
  elif ! plan_only "$HOME/.zshrc.local 생성 (시크릿 보관용 템플릿)"; then
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
  fi

  echo -e "\n[선택] Infracost 비용 분석 도구 로그인"
  if [ "$DRY_RUN" = true ]; then
    echo "   [dry-run] Infracost API 키 등록 여부 확인 및 대화형 로그인"
  elif [ -t 0 ]; then
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
  if [ "$DRY_RUN" = true ]; then
    echo "🔎 DRY-RUN 종료: 위 [dry-run] 항목이 실제 실행 시 수행될 작업입니다."
    echo "💡 실제 적용은 --dry-run 없이 실행하세요: bash setup.sh"
  else
    echo "✅ 완벽합니다! 모든 인프라 환경 구성이 진짜 완료되었습니다."
    echo "💡 적용을 위해 터미널을 다시 열거나 'exec zsh'을 입력하세요."
  fi
  echo "========================================================="
}

# =============================================================================
# 메인 오케스트레이터 (Entrypoint)
# =============================================================================
main() {
  # 부분 실행 옵션 등 확장을 위해 구조화됨
  step1_install_os_packages
  step2_setup_zsh_and_plugins
  step3_setup_stow_symlinks
  step4_install_mise_and_tools
  step5_deploy_agent_rules
  step6_security_and_interactive_setup
}

# 스크립트가 직접 실행되었을 때만 main 함수 호출 (source 로 로드될 경우 대비)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi

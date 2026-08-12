#!/usr/bin/env bash
# bootstrap.sh
# 🚀 인프라 엔지니어 로컬 환경 셋업 진입점
# 필수 도구(mise, just, ansible)를 준비한 후 제어권을 Justfile과 Ansible Playbook으로 위임합니다.

set -euo pipefail
export ANSIBLE_HOME="$HOME/.cache/ansible"
# 실행 경로에 무관하게 스크립트 위치 기준 절대경로 확정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 0. sudo 인증 티켓을 스크립트 맨 앞에서 계정 전체로 공유되게 만들어(!tty_tickets)
# 뒷단(ansible)에서 다시 묻지 않게 한다. ansible-core 2.19+가 become(sudo) 워커를
# setsid()로 분리된 세션에서 실행하면서(ansible/ansible#86149, #85536 — 의도된 사양
# 변경) 기본 정책(tty_tickets)상 그 세션이 이 티켓을 못 보고 "sudo: a password is
# required"로 실패하는 실제 재현된 버그를 막는다. 비밀번호를 캡처해 재사용하는
# 대신(노출 구간 생김) sudo 자체 캐시 범위를 넓히는 방식이며, Homebrew install.sh와
# 동일하게 sudo -v를 한 번만 받는다. 이미 티켓이 있는지 미리 걸러내지 않는 이유:
# 걸러내면 아래 sudo-rs 전환·드롭인 설치가 스킵돼 이 블록이 막으려는 문제가 그대로
# 재현되는데, sudo -v는 티켓이 유효해도 프롬프트 없이 갱신만 하는 멱등 호출이라
# 무조건 호출해도 안전하다.
if command -v apt-get &>/dev/null || command -v dnf &>/dev/null; then
  sudo -v

  # Ubuntu가 기본 sudo를 sudo-rs(Rust 재구현)로 넘기는 과도기라 이 계정에서 활성화돼
  # 있을 수 있다. sudo-rs는 -S(stdin) 비밀번호 프롬프트를 "[sudo: <prompt>] Password:"로
  # 감싸는데, Ansible sudo become 플러그인은 자신이 -p로 넘긴 문자열이 줄 맨 앞에 그대로
  # 나오길 기대해 이를 인식 못 하고 "Timed out waiting for become success..."로 멈춘다
  # (실제 재현된 버그, ansible/ansible#85837). classic sudo(sudo.ws)는 래핑 없이 그대로
  # 출력하므로, sudo-rs가 활성 상태고 sudo.ws가 같이 설치돼 있으면(Ubuntu 전환기 동안
  # 둘 다 패키지로 제공) 자동 전환해둔다.
  if sudo --version 2>/dev/null | grep -qi 'sudo-rs' && [ -x /usr/bin/sudo.ws ]; then
    sudo update-alternatives --set sudo /usr/bin/sudo.ws >/dev/null
    echo "✅ sudo-rs → classic sudo(sudo.ws)로 전환했습니다 (Ansible become 프롬프트 호환성 문제 회피, ansible/ansible#85837)."
  fi

  SUDOERS_DROPIN="/etc/sudoers.d/99-dotfiles-$(whoami)-shared-timestamp"
  if [ ! -f "$SUDOERS_DROPIN" ]; then
    if sudo --version 2>/dev/null | grep -qi 'sudo-rs'; then
      # classic sudo 전환 시도 후에도 여전히 sudo-rs라면(sudo.ws가 없는 배포판 등)
      # 사용자별(Defaults:user) 항목 자체를 아직 지원하지 않아(trifectatechfoundation/
      # sudo-rs FAQ) 이 드롭인을 설치할 수 없으므로 실패가 뻔한 visudo 호출 없이 바로
      # 건너뛴다. Justfile의 setup/setup-dryrun이 드롭인 파일 유무를 보고
      # --ask-become-pass로 미리 물어보도록 처리돼 있어 Ansible 단계 도중 예고 없이
      # 끊기진 않는다(단, 위 프롬프트 래핑 버그 자체는 --ask-become-pass로도 우회 안 돼
      # classic sudo 전환이 유일한 해결책).
      echo "ℹ️ sudo-rs 환경이라 세션 간 sudo 티켓 공유는 지원되지 않습니다 — 건너뜁니다. Ansible 단계 시작 시 비밀번호를 한 번 더 입력하게 됩니다."
    else
      TMP_SUDOERS=$(mktemp)
      echo "Defaults:$(whoami) !tty_tickets" >"$TMP_SUDOERS"
      # visudo -c로 문법을 먼저 검증하지 않고 /etc/sudoers.d/에 바로 설치하면, 오타 하나로
      # 시스템 전체의 sudo가 깨질 위험이 있다(하드 블록해야 하는 이유).
      if sudo visudo -cf "$TMP_SUDOERS" >/dev/null 2>&1; then
        sudo install -m 0440 -o root -g root "$TMP_SUDOERS" "$SUDOERS_DROPIN"
        echo "✅ sudo 인증 티켓이 이 계정 전체에서 공유되도록 설정했습니다 ($SUDOERS_DROPIN)."
      else
        echo "⚠️ sudoers 드롭인 문법 검증 실패 — 자동 설정을 건너뜁니다. 뒤에서 Ansible 단계가 비밀번호를 다시 요구할 수 있습니다." >&2
      fi
      rm -f "$TMP_SUDOERS"
    fi
  fi
fi

# 1. OS 패키지 매니저 판별
# stow는 ansible의 packages 역할이 나중에 다시 설치하지만(멱등), mise config.toml을
# ansible보다 먼저 링크해야 해서(아래 3단계) 여기서 미리 확보해둔다.
# gnupg(gpg)는 아래 2단계에서 mise 설치 스크립트의 GPG 서명을 검증하는 데 필요해
# ansible packages 롤(Docker GPG 검증용)보다 먼저 여기서 확보해둔다.
if command -v apt-get &>/dev/null; then
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl git unzip stow gnupg
elif command -v dnf &>/dev/null; then
  sudo dnf install -y curl git unzip stow gnupg2
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
# curl|sh를 그대로 실행하는 대신, mise 공식 릴리스 GPG 키로 설치 스크립트 서명을
# 검증한 뒤 실행한다 (Docker 롤의 GPG 지문 검증과 동일한 신뢰 수준).
# 참고: mise 문서의 "공식 저장소" 설치(apt는 extrepo, dnf는 ppa)는 실측 결과 미채택 —
# apt: Debian 공식 extrepo-data 큐레이션 목록에 mise 항목이 없어 `extrepo enable mise`가
# 실패. dnf: ppa:jdxcode/mise는 Launchpad 기반이라 Ubuntu 전용이라 dnf 계열엔 해당 없음.
# 배포판에 좌우되지 않는 GPG 서명 검증 방식을 모든 OS에 공통 적용한다.
if [ ! -x "$HOME/.local/bin/mise" ]; then
  echo "=> Installing mise (GPG 서명 검증 후 설치, https://mise.jdx.dev)..."
  MISE_GPG_HOME="$(mktemp -d)"
  MISE_INSTALL_SCRIPT="$MISE_GPG_HOME/install.sh"
  # https://mise.jdx.dev/installing-mise.html 에 명시된 mise 릴리스 서명 키 지문
  MISE_GPG_KEY_FP="24853EC9F655CE80B48E6C3A8B81C9D17413A06D"

  curl -fsSL https://mise.jdx.dev/gpg-key.pub | gpg --homedir "$MISE_GPG_HOME" --import -q
  IMPORTED_FP="$(gpg --homedir "$MISE_GPG_HOME" --with-colons --fingerprint | awk -F: '/^fpr:/ {print $10; exit}')"
  if [ "$IMPORTED_FP" != "$MISE_GPG_KEY_FP" ]; then
    echo "❌ [Hard Block] mise GPG 키 지문이 예상 값과 다릅니다 (공급망 검증 실패)." >&2
    echo "   예상: $MISE_GPG_KEY_FP" >&2
    echo "   실제: $IMPORTED_FP" >&2
    rm -rf "$MISE_GPG_HOME"
    exit 1
  fi

  # 검증 판정에 사람용 출력("Good signature from")을 쓰지 않는다. 두 가지 문제가 있었다:
  #   1. 그 문구는 gpg 의 번역 대상이라 로케일에 따라 달라진다(gnupg 에 ko 번역이 없어
  #      한국어 환경에서는 우연히 영어가 나왔을 뿐, ja/de 등에서는 정상 서명도 실패 판정).
  #   2. 파이프라인 실패를 잡지 않아, 서명이 실제로 틀렸을 때 gpg 가 0 이 아닌 코드로
  #      끝나면 set -euo pipefail 이 바로 아래 안내 문구에 닿기도 전에 스크립트를 죽였다
  #      — 즉 정작 필요한 Hard Block 메시지가 한 번도 출력될 수 없었다.
  # --status-fd 로 나오는 기계용 상태 줄(GOODSIG)은 번역되지 않으므로 이쪽을 판정에 쓴다.
  gpg_rc=0
  curl -fsSL https://mise.jdx.dev/install.sh.sig |
    gpg --homedir "$MISE_GPG_HOME" --status-fd 3 --decrypt \
      >"$MISE_INSTALL_SCRIPT" 3>"$MISE_GPG_HOME/status.log" 2>"$MISE_GPG_HOME/verify.log" || gpg_rc=$?
  if [ "$gpg_rc" -ne 0 ] || ! grep -q '^\[GNUPG:\] GOODSIG ' "$MISE_GPG_HOME/status.log"; then
    echo "❌ [Hard Block] mise 설치 스크립트 GPG 서명 검증 실패." >&2
    cat "$MISE_GPG_HOME/verify.log" >&2
    rm -rf "$MISE_GPG_HOME"
    exit 1
  fi

  sh "$MISE_INSTALL_SCRIPT"
  rm -rf "$MISE_GPG_HOME"
fi

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

# =============================================================================
# ZSH Configuration (Optimized for Infrastructure Engineers)
# =============================================================================

# --- [Oh My Zsh Core] ---
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git kubectl terraform zsh-autosuggestions zsh-syntax-highlighting)

# HIST_STAMPS: oh-my-zsh.sh 로드 이전 선언 필수 (history.zsh 로드 시점 확정)
HIST_STAMPS="yyyy-mm-dd"        # 히스토리에 날짜/시간 기록

source "$ZSH/oh-my-zsh.sh"

# --- [ZSH History Settings (Pro)] ---
setopt HIST_IGNORE_ALL_DUPS     # 중복된 명령어는 히스토리에 한 번만 기록
setopt HIST_IGNORE_SPACE        # 띄어쓰기로 시작하는 명령어는 기록 무시 (시크릿 보호용)
setopt HIST_REDUCE_BLANKS       # 명령어 내의 불필요한 공백 제거 후 기록
setopt SHARE_HISTORY            # 여러 터미널 창 간에 히스토리 실시간 공유

# --- [인프라 엔지니어 필수 설정] ---
# bin/{hooks,utils,linters}의 실행 스크립트는 ansible ai_agent 롤이 ~/.local/bin에
# 이미 심볼릭 링크하므로 여기서 dotfiles 하위 경로를 따로 PATH에 또 추가하지 않는다.
# bin/lib은 소스 전용이라 원래도 실행 권한이 없어 ansible이 링크하지 않고, 항상
# 소스하는 스크립트의 상대 경로로만 불려 PATH가 필요 없다.
export PATH="$HOME/.local/bin:$PATH"

# Ansible 캐시/찌꺼기 프로젝트 오염 방지 (XDG 호환 캐시 디렉토리로 격리)
export ANSIBLE_HOME="$HOME/.cache/ansible"

# Bicep (libicu 부재 환경) Invariant 모드 강제 활성화
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

# 1. 파일/에디터 관련
# OS별 파일 탐색기 별칭 분기 처리 (WSL, 리눅스, macOS)
if grep -qi microsoft /proc/version 2>/dev/null; then
  alias e='explorer.exe .'
elif [[ "$OSTYPE" == darwin* ]]; then
  alias e='open .'
elif command -v xdg-open &>/dev/null; then
  alias e='xdg-open .'
fi
alias c='code .'
alias ll='ls -alF'

# 2. Kubernetes 관련 (mise로 설치된 도구 연동)
alias k='kubectl'
alias kx='kubectx'
alias kn='kubens'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kga='kubectl get all'
alias kdp='kubectl describe pod'
alias klogs='kubectl logs -f'
alias kex='kubectl exec -i -t'
alias knet='kubectl run netshoot --image=nicolaka/netshoot --rm -it --restart=Never -- zsh'
alias kgd='kubectl get deployments'
alias kgn='kubectl get nodes'
alias krm='kubectl delete'
alias kw='watch kubectl'

# 2.5. Docker & Helm 관련
alias d='docker'
# ansible docker 롤이 설치하는 건 docker-compose-plugin(v2, `docker compose` 서브커맨드)이다.
# v1 단독 바이너리(docker-compose)는 이 저장소 어디서도 설치하지 않아 항상 command not found였다.
alias dc='docker compose'
alias h='helm'

# 3. Terraform 관련
alias tf='terraform'
alias tfi='terraform init'
alias tff='terraform fmt -recursive'
alias tfv='terraform validate'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfw='terraform workspace'

# 4. 도구 환경 활성화 (Mise)
# mise 존재 확인 후 eval 적용 ("command not found" 에러 방지)
#
# 재실행 가드로 환경 변수(export)를 쓰면 안 된다. 환경 변수는 자식 프로세스로 상속되는
# 반면 activate가 만드는 것은 셸 함수/훅이라 상속되지 않아서, 중첩 zsh나 `exec zsh`에서는
# "가드는 켜져 있는데 훅은 없는" 상태가 된다(실측: 중첩 셸에서 _mise_hook 0개 — 디렉토리별
# 도구 버전 전환과 mise 환경 주입이 통째로 무효화됨). 하필 bootstrap.sh 마지막 안내가
# `exec zsh`이고 tmux/IDE 터미널도 전부 기존 셸에서 파생된다.
# 그래서 별도 플래그 대신 "이 셸에 훅이 실제로 있는가"를 직접 본다 — 이미 낡은 플래그를
# 환경에 물려받은 셸에서도 자가 치유되고, 같은 셸에서 .zshrc를 두 번 source 해도
# 중복 활성화되지 않는다.
if [ -x "$HOME/.local/bin/mise" ] && ! typeset -f _mise_hook >/dev/null 2>&1; then
  eval "$(~/.local/bin/mise activate zsh)"
fi

# 5. fzf (Fuzzy Finder) 단축키 및 자동완성 연동 (Mise 설치 기준)
# fzf --zsh는 0.48.0+에서만 지원. mise로 관리되는 버전이 PATH에 먹히지 않으면
# 시스템 fzf(구버전)을 주울 수 있으므로 버전 확인 후 실행.
# 가드로 위젯 정의 여부를 보는 이유는 위 mise 블록과 동일하다(export 가드는 중첩 셸에서
# Ctrl-R/Ctrl-T 키바인딩을 조용히 잃게 만든다).
#
# 버전 비교는 major*1000+minor 로 인코딩한다. 예전엔 `printf "%d%03d"` 로 만든 문자열을
# 48000 과 비교했는데, fzf 는 아직 0.x 라 0.48.0 도 0.74.2 도 "0048"/"0074" 가 되어
# 임계값을 넘을 수가 없었다 — 즉 어떤 버전에서도 이 블록이 실행된 적이 없다(실측).
# 게다가 앞의 0 때문에 셸 산술이 8진수로 해석해 "0048" 은 아예 오류가 난다.
# 0.48.0 -> 48, 0.74.2 -> 74, 미래의 1.0 -> 1000 이 되도록 패딩 없이 계산한다.
if command -v fzf &>/dev/null && ! typeset -f fzf-history-widget >/dev/null 2>&1; then
  _fzf_ver=$(fzf --version 2>/dev/null | awk '{print $1}' | awk -F. '{print ($1 * 1000) + $2}')
  if [ -n "$_fzf_ver" ] && [ "$_fzf_ver" -ge 48 ] 2>/dev/null; then
    eval "$(fzf --zsh)"
  fi
  unset _fzf_ver
fi
# ------------------------------------


# --- [기타 도구 및 유틸리티] ---
alias ap='ansible-playbook'
alias myip='curl -s ifconfig.me'

# 로컬 시크릿/환경 변수 분리 파일 로드
[ -f ~/.zshrc.local ] && source ~/.zshrc.local
# 앞으로 터미널에 src만 치면 자동으로 .zshrc가 새로고침됩니다.
alias src='source ~/.zshrc'

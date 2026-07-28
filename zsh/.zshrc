# =============================================================================
# ZSH Configuration (Optimized for Infrastructure Engineers)
# =============================================================================

# --- [Oh My Zsh Core] ---
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git kubectl terraform zsh-autosuggestions zsh-syntax-highlighting)

# HIST_STAMPS는 반드시 oh-my-zsh.sh 로드 전에 선언해야 한다. lib/history.zsh가 로드 시점에
# case ${HIST_STAMPS-} 로 한 번 읽어 history 별칭을 확정하므로, 로드 후에 선언하면 값이
# 무시된다(2026-07-27 실측: 로드 후 선언 시 history=omz_history, 로드 전 선언 시 -i 적용).
HIST_STAMPS="yyyy-mm-dd"        # 히스토리에 날짜/시간 기록

source $ZSH/oh-my-zsh.sh

# --- [ZSH History Settings (Pro)] ---
setopt HIST_IGNORE_ALL_DUPS     # 중복된 명령어는 히스토리에 한 번만 기록
setopt HIST_IGNORE_SPACE        # 띄어쓰기로 시작하는 명령어는 기록 무시 (시크릿 보호용)
setopt HIST_REDUCE_BLANKS       # 명령어 내의 불필요한 공백 제거 후 기록
setopt SHARE_HISTORY            # 여러 터미널 창 간에 히스토리 실시간 공유

# --- [인프라 엔지니어 필수 설정] ---
export PATH="$HOME/.local/bin:$PATH"

# Bicep(.NET 기반)이 libicu 없는 Ubuntu 환경에서도 실행되도록 Invariant 모드 강제 활성화
# (pre-flight-check.sh의 validate_bicep()과 동일한 설정 - 훅 밖 터미널 직접 실행 시에도 적용)
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

# 1. 파일/에디터 관련
# explorer.exe 는 WSL 에서만 존재한다. 리눅스 네이티브나 macOS 에서 이 별칭을 그대로 두면
# 존재하지 않는 명령을 가리켜 command not found 로 끝나므로, 각 환경의 파일 탐색기로 건다.
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
alias dc='docker-compose'
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
# 아래 fzf 블록과 동일하게 존재 여부를 먼저 확인한다. 무방비로 eval하면 mise 설치 전이나
# 설치 실패 상태에서 셸을 열 때마다 "command not found"가 출력된다.
if [ -x "$HOME/.local/bin/mise" ]; then
  eval "$(~/.local/bin/mise activate zsh)"
fi

# 5. fzf (Fuzzy Finder) 단축키 및 자동완성 연동 (Mise 설치 기준)
if command -v fzf &> /dev/null; then
  eval "$(fzf --zsh)"
fi
# ------------------------------------


# --- [기타 도구 및 유틸리티] ---
alias ap='ansible-playbook'
alias myip='curl -s ifconfig.me'

# 로컬 환경 변수(GitHub Token, 클라우드 API Key 등 시크릿)를 안전하게 관리하기 위한 분리 파일 로드
[ -f ~/.zshrc.local ] && source ~/.zshrc.local
# 앞으로 터미널에 src만 치면 자동으로 .zshrc가 새로고침됩니다.
alias src='source ~/.zshrc'




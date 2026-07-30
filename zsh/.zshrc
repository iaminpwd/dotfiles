# =============================================================================
# ZSH Configuration (Optimized for Infrastructure Engineers)
# =============================================================================

# --- [Oh My Zsh Core] ---
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git kubectl terraform zsh-autosuggestions zsh-syntax-highlighting)

# HIST_STAMPS: oh-my-zsh.sh 로드 이전 선언 필수 (history.zsh 로드 시점 확정)
HIST_STAMPS="yyyy-mm-dd"        # 히스토리에 날짜/시간 기록

source $ZSH/oh-my-zsh.sh

# --- [ZSH History Settings (Pro)] ---
setopt HIST_IGNORE_ALL_DUPS     # 중복된 명령어는 히스토리에 한 번만 기록
setopt HIST_IGNORE_SPACE        # 띄어쓰기로 시작하는 명령어는 기록 무시 (시크릿 보호용)
setopt HIST_REDUCE_BLANKS       # 명령어 내의 불필요한 공백 제거 후 기록
setopt SHARE_HISTORY            # 여러 터미널 창 간에 히스토리 실시간 공유

# --- [인프라 엔지니어 필수 설정] ---
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/dotfiles/bin/hooks:$HOME/dotfiles/bin/utils:$HOME/dotfiles/bin/linters:$HOME/dotfiles/bin/lib:$PATH"

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
# mise 존재 확인 후 eval 적용 ("command not found" 에러 방지)
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

# 로컬 시크릿/환경 변수 분리 파일 로드
[ -f ~/.zshrc.local ] && source ~/.zshrc.local
# 앞으로 터미널에 src만 치면 자동으로 .zshrc가 새로고침됩니다.
alias src='source ~/.zshrc'




# =============================================================================
# ZSH Configuration (Optimized for Infrastructure Engineers)
# =============================================================================

# --- [Oh My Zsh Core] ---
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git kubectl terraform zsh-autosuggestions zsh-syntax-highlighting)
source $ZSH/oh-my-zsh.sh

# --- [ZSH History Settings (Pro)] ---
HIST_STAMPS="yyyy-mm-dd"        # 히스토리에 날짜/시간 기록
setopt HIST_IGNORE_ALL_DUPS     # 중복된 명령어는 히스토리에 한 번만 기록
setopt HIST_IGNORE_SPACE        # 띄어쓰기로 시작하는 명령어는 기록 무시 (시크릿 보호용)
setopt HIST_REDUCE_BLANKS       # 명령어 내의 불필요한 공백 제거 후 기록
setopt SHARE_HISTORY            # 여러 터미널 창 간에 히스토리 실시간 공유

# --- [인프라 엔지니어 필수 설정] ---
export PATH="$HOME/.local/bin:$PATH"

# 1. 파일/에디터 관련
alias e='explorer.exe .'
alias c='code .'
alias ll='ls -alF'

# 2. Kubernetes 관련 (mise로 설치된 도구 연동)
alias k='kubectl'
alias kx='kubectx'
alias kn='kubens'
alias kgp='kubectl get pod'
alias kgs='kubectl get svc'
alias kga='kubectl get all'
alias knet='kubectl run netshoot --image=nicolaka/netshoot --rm -it --restart=Never -- zsh'

# 3. Terraform 관련
alias tf='terraform'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfd='terraform destroy'

# 4. 도구 환경 활성화 (Mise)
eval "$(~/.local/bin/mise activate zsh)"

# 5. fzf (Fuzzy Finder) 단축키 및 자동완성 연동 (apt로 설치된 경로 기준)
[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && source /usr/share/doc/fzf/examples/key-bindings.zsh
[ -f /usr/share/doc/fzf/examples/completion.zsh ] && source /usr/share/doc/fzf/examples/completion.zsh
# ------------------------------------

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.

# 🤖 AI Prompt Context Generator (전체 인프라 코드 한 방에 추출하기)
# 확장자 지정 순서를 변경하고 실행 셸을 bash로 명시하여 충돌을 원천 차단한 수정본
alias catcode='fdfind -H -E .git -E .terraform -e tf -e tfvars -e json -e yml -e yaml -e j2 -e ps1 -e py -e toml -e txt -e sh -x bash -c '\''printf "\n# FILE: %s\n" "{}"; cat "{}"'\'' > all_code.txt'
# 앞으로 터미널에 src만 치면 자동으로 .zshrc가 새로고침됩니다.
alias src='source ~/.zshrc'

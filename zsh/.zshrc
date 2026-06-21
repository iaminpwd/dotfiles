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

# Ubuntu 패키지명 충돌 해결 (사용자 편의성)
if command -v fdfind &> /dev/null; then
  alias fd='fdfind'
fi

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

# 4. 도구 환경 활성화 (Mise)
eval "$(~/.local/bin/mise activate zsh)"

# 5. fzf (Fuzzy Finder) 단축키 및 자동완성 연동 (Mise 설치 기준)
if command -v fzf &> /dev/null; then
  eval "$(fzf --zsh)"
fi
# ------------------------------------

# 🤖 AI Prompt Context Generator (전체 인프라 코드 한 방에 추출하기)
# 확장자 지정 순서를 변경하고 실행 셸을 bash로 명시하여 충돌을 원천 차단한 수정본
alias catcode='fdfind -H -E .git -E .terraform -e tf -e tfvars -e json -e yml -e yaml -e j2 -e ps1 -e py -e toml -e txt -e sh -x bash -c '\''printf "\n# FILE: %s\n" "{}"; cat "{}"'\'' > all_code.txt'
# 로컬 환경 변수(GitHub Token, 클라우드 API Key 등 시크릿)를 안전하게 관리하기 위한 분리 파일 로드
[ -f ~/.zshrc.local ] && source ~/.zshrc.local
# 앞으로 터미널에 src만 치면 자동으로 .zshrc가 새로고침됩니다.
alias src='source ~/.zshrc'

# =============================================================================
# 🤖 AI 프롬프트 자동 상속 훅 (Auto-Symlink)
# =============================================================================
# ~/aws, ~/kubernetes 등 부모 폴더에 RULES.md가 존재하는 상태에서,
# 하위의 Git 레포지토리 폴더로 `cd`하여 진입할 경우 자동으로 글로벌 룰북을 로컬로 링크합니다.
function auto_symlink_ai_rules() {
  # 1. 현재 폴더가 Git 레포지토리 루트인지 확인
  if [ ! -d ".git" ]; then
    return
  fi

  # 2. 현재 경로에서 환경명 추출 (패턴: */workspace/<env_name>/src/*)
  local env_name=""
  case "$PWD" in
    */workspace/*/src/*)
      env_name="${PWD#*/workspace/}"
      env_name="${env_name%%/src/*}"
      ;;
    *)
      return
      ;;
  esac

  local dotfiles_env_dir="$HOME/dotfiles/contexts/$env_name"
  
  # 3. 환경 원본 폴더 존재 여부 확인
  if [ ! -d "$dotfiles_env_dir" ]; then
    return
  fi
  
  # 1. AI 룰북 자동 링크 (Gemini 단일)
  local target_md="$dotfiles_env_dir/RULES.md"
  if [ -f "$target_md" ]; then
    local current_link=""
    [ -L ".gemini/00-global-rules.md" ] && current_link=$(readlink ".gemini/00-global-rules.md")
    if [ "$current_link" != "$target_md" ]; then
      mkdir -p .gemini
      ln -sfn "$target_md" .gemini/00-global-rules.md
      echo "🤖 AI 룰북(RULES.md) 동적 링크 주입(갱신) 완료 (Gemini)"
    fi
  fi

  # 2. AI 최적화 룰 다이렉트 자동 링크
  local target_aiexclude="$dotfiles_env_dir/.aiexclude"
  if [ -f "$target_aiexclude" ]; then
    local current_aiexclude_link=""
    [ -L ".aiexclude" ] && current_aiexclude_link=$(readlink ".aiexclude")
    if [ "$current_aiexclude_link" != "$target_aiexclude" ]; then
      ln -sfn "$target_aiexclude" .aiexclude
      echo "🤖 AI 최적화 룰(.aiexclude) 다이렉트 자동 상속(갱신) 완료: .aiexclude 링크 생성됨"
    fi
  fi
}
# 디렉토리 이동(cd) 이벤트 발생 시 위 함수를 자동으로 실행하도록 Zsh 훅 등록
add-zsh-hook chpwd auto_symlink_ai_rules

# =============================================================================
# 🤖 컨텍스트 000 마스터 코어 자동 링크 훅 (SSOT Auto-Symlink)
# =============================================================================
# ~/dotfiles/contexts/gcp/.contexts 처럼 새로운 룰 폴더로 진입할 경우,
# 최상위 000-universal-core.md 마스터 엔진을 자동으로 심볼릭 링크합니다.
function auto_symlink_contexts_core() {
  # 1차 필터링: contexts 폴더 하위일 때만 발동
  case "$PWD" in
    */contexts/*)
      local target_dir=""
      
      # 2차 판별: 진입한 곳이 .contexts 안인지, 아니면 상위 도메인 폴더인지
      case "$PWD" in
        */\.contexts)
          target_dir="${PWD%/.contexts}"
          ;;
        *)
          # 현재 경로의 부모 폴더가 contexts 인지 확인하여 1-depth 폴더에만 발동 (예: contexts/gcp)
          local parent_dir=$(dirname "$PWD")
          if [[ "${parent_dir}" == */contexts ]]; then
            target_dir="$PWD"
          else
            return
          fi
          ;;
      esac
      
      # 마스터 코어 존재 여부 확인
      local master_core="$target_dir/../000-universal-core.md"
      # dotfiles 워크스페이스는 자체 000 파일이 있으므로 심볼릭 링크 생성을 제외합니다.
      if [ -f "$master_core" ] && [ "$(basename "$target_dir")" != "dotfiles" ]; then
          # 디렉토리가 없으면 즉시 생성
          mkdir -p "$target_dir/.contexts"
          
          local target_link="$target_dir/.contexts/000-universal-core.md"
          local current_link=""
          
          [ -L "$target_link" ] && current_link=$(readlink "$target_link")
          
          # cd(이동) 명령어 없이 제자리에서 절대/상대 경로 조합으로 심볼릭 링크 꽂기 (무한루프 방지)
          if [ "$current_link" != "../../000-universal-core.md" ]; then
              ln -sfn "../../000-universal-core.md" "$target_link"
              echo "🤖 마스터 프롬프트 엔진(000-universal-core) 동적 링크 주입 완료"
          fi
      fi
      ;;
  esac
}
add-zsh-hook chpwd auto_symlink_contexts_core

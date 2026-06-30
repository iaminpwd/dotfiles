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
        */references)
          target_dir="${PWD%/references}"
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
      
      # 000 마스터 코어가 상위에 존재하는 정상적인 AI 컨텍스트 폴더인지 검증
      local master_core="$target_dir/../000-universal-core.md"
      if [ -f "$master_core" ] && [ "$(basename "$target_dir")" != "dotfiles" ]; then
          # 디렉토리가 없으면 즉시 생성
          mkdir -p "$target_dir/references"
          
          local target_link="$target_dir/references/000-universal-core.md"
          local current_link=""
          
          [ -L "$target_link" ] && current_link=$(readlink "$target_link")
          
          # cd(이동) 명령어 없이 제자리에서 절대/상대 경로 조합으로 심볼릭 링크 꽂기 (무한루프 방지)
          if [ "$current_link" != "../../000-universal-core.md" ]; then
              ln -sfn "../../000-universal-core.md" "$target_link"
              echo "🤖 마스터 프롬프트 엔진(000-universal-core) 동적 링크 주입 완료"
          fi

          # [NEW] .base.aiexclude 템플릿 복사 로직 (멱등성 보장)
          local base_aiexclude="$target_dir/../.base.aiexclude"
          local target_aiexclude="$target_dir/.aiexclude"
          if [ -f "$base_aiexclude" ] && [ ! -f "$target_aiexclude" ]; then
              cp "$base_aiexclude" "$target_aiexclude"
              echo "🤖 범용 AI Exclude 템플릿(.aiexclude) 동적 셋업 완료"
          fi
      fi
      ;;
  esac
}
add-zsh-hook chpwd auto_symlink_contexts_core

# 🤖 워크스페이스 스킬 자동 링크 훅 (Workspace Skills Auto-Symlink)
# =============================================================================
# ~/workspace/*/src/* (프로젝트 폴더) 로 진입할 경우,
# 프로젝트가 속한 상위 환경(aws, k8s 등)을 추출하여,
# 해당 도메인의 references 하위 파일들을 선별(000 제외)하여 핀셋 주입합니다.
function auto_symlink_workspace_skills() {
  case "$PWD" in
    $HOME/workspace/*/src/*)
      # 현재 경로가 src/ 바로 아래 1-depth 인지 확인 (루트 프로젝트 디렉토리)
      local rel_path="${PWD#$HOME/workspace/*/src/}"
      if [[ "$rel_path" != */* ]]; then
        # 워크스페이스 환경명 추출 (예: aws, k8s, azure)
        local env_path="${PWD#$HOME/workspace/}"
        local env_name="${env_path%%/*}"
        
        local target_skills_dir="$PWD/.agents/skills"
        local contexts_dir="$HOME/dotfiles/contexts"
        local env_contexts_dir="$contexts_dir/$env_name/references"
        
        if [ -d "$env_contexts_dir" ]; then
          # 기존 엉뚱한 스킬 링크 완전 초기화
          \rm -rf "$target_skills_dir" 2>/dev/null || true
          
          local skill_dir="$target_skills_dir/$env_name"
          local ref_dir="$skill_dir/references"
          mkdir -p "$ref_dir"
          
          # SKILL.md 동적 생성 및 템플릿 복사 (에이전트가 도메인 스킬을 인지하도록 필수)
          if [ -f "$contexts_dir/$env_name/SKILL.md" ]; then
            cp "$contexts_dir/$env_name/SKILL.md" "$skill_dir/SKILL.md"
          else
            echo "---" > "$skill_dir/SKILL.md"
            echo "name: ${env_name} Operations" >> "$skill_dir/SKILL.md"
            echo "description: Rules and guidelines for ${env_name} environment." >> "$skill_dir/SKILL.md"
            echo "---" >> "$skill_dir/SKILL.md"
            echo "# ${env_name} Skill" >> "$skill_dir/SKILL.md"
            echo "Please refer to the files in the \`references/\` directory for detailed instructions." >> "$skill_dir/SKILL.md"
          fi
          
          # references 내의 파일들 중 000-universal-core.md 등 000 제외하고 링크
          for ctx_file in "$env_contexts_dir"/*.md; do
            [ -e "$ctx_file" ] || continue
            local fname=$(basename "$ctx_file")
            if [[ "$fname" != 000* ]]; then
              ln -sfn "$ctx_file" "$ref_dir/$fname"
            fi
          done
          
          # .aiexclude 동적 주입 (프로젝트 루트)
          if [ -f "$contexts_dir/$env_name/.aiexclude" ]; then
            cp "$contexts_dir/$env_name/.aiexclude" "$PWD/.aiexclude"
          fi
          
          echo "🚀 [AI Auto-Setup] 도메인 특화 프롬프트 룰북(${env_name}) 선별 주입 완료"
          echo "🔒 [AI Auto-Setup] AI 컨텍스트 접근 제어(.aiexclude) 적용 완료"
        fi
      fi
      ;;
  esac
}
add-zsh-hook chpwd auto_symlink_workspace_skills

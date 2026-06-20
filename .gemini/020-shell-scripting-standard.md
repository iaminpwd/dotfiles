<dotfiles_shell_scripting_standard>
# 컨텍스트 모듈: Dotfiles 환경 설정 및 셸 스크립트 작성 표준

본 모듈은 `dotfiles` 워크스페이스 내부의 자동화 스크립트(`setup.sh`, `install.sh`) 및 시스템 셸 설정(`zshrc`, `bashrc`, `tmux.conf` 등) 작성에만 한정하여 적용됩니다.

## 1. 셸 스크립트 강건성 (Robustness) 및 멱등성
- **[MUST] Bash Strict Mode:** 인프라를 프로비저닝하는 셸 스크립트의 최상단에는 반드시 `set -euo pipefail` 구문을 선언하여 파이프라인 중간 단계 에러나 미선언 변수 참조 시 즉각 실패(Fail-Fast)하도록 방어하십시오.
- **[MUST] Explicit Idempotency (멱등성 보장 강제):** 스크립트를 여러 번 반복 실행하더라도 셸 설정이 중복되거나 도구가 재설치되지 않도록, 반드시 패키지 설치 전 상태 검증 방어 로직(예: `if ! command -v <tool>; then`)을 포함하십시오.
- **[MUST] Temporary File Cleanup (임시 리소스 반환):** `/tmp` 경로 등에 생성된 임시 파일들은 스크립트 성공 여부(SIGINT 등)와 무관하게 완전히 정리되도록 `trap 'rm -rf /tmp/xxx' EXIT` 로직을 필수적으로 구현하십시오.
- **[PREFER] WSL2 / Cross-Platform Awareness:** WSL2 환경을 고려하여, Windows의 마운트 경로(`/mnt/c/`)에서 실행되는 것을 감지하고 방어하거나 퍼미션(chmod) 오류를 우회하는 로직을 적극 포함하십시오.

## 2. 파일 수정 및 조작의 극단적 안전성
- **[MUST] Safe Configuration Appending:** 셸 설정을 `.zshrc` 등에 추가(Append)할 때, 반드시 먼저 `grep -q "문자열"`로 설정 존재 여부를 사전에 검사한 후 안전하게 추가하십시오.
- **[MUST] Symlink Awareness (GNU Stow Pattern):** 본 환경은 `stow`를 이용해 홈 디렉토리(`~`)로 설정 파일을 심볼릭 링크하는 구조입니다. AI는 반드시 `~/dotfiles/zsh/.zshrc` 등 **Stow의 원본 타겟(Source)**만을 조작하여 심볼릭 링크 아키텍처를 유지하십시오.
- **[MUST] Safe File Backup:** 핵심 설정 파일을 덮어쓰기 전에는 시스템 마비 복원을 위해 타임스탬프가 적용된 백업 파일(`cp ~/.zshrc ~/.zshrc.bak.$(date +%F)`)을 생성하는 파이프라인을 포함하십시오.
- **[NEVER] Sudo Privilege Abuse:** 패키지 설치 시 시스템 소유권 파괴를 막기 위해 맹목적인 `sudo` 사용을 금지합니다. 홈 디렉토리 패스(`~/.local/bin`) 기반의 User-Level 격리 설치를 최우선 제안하십시오.

## 3. 검증 및 런타임 환경 보호
- **[Trigger: After Script Edit] Syntax Validation (문법 자가 검증):**
  > `setup.sh`나 `.zshrc`를 수정한 직후, `000` 모듈의 '자율적 자가 치유' 트리거를 백그라운드에서 발동시킬 때, 검증 수단으로 반드시 터미널에서 `bash -n <file>` 또는 `zsh -n <file>` 구문 검사를 돌려 스스로 사전 색출하십시오.
- **[NEVER] Protect Core Architecture:** 셸 설정 내의 `auto_symlink_gemini_rules` 훅(Zsh chpwd)이나 헬퍼 앨리어스(`batcat -> bat`, `catcode`)는 본 AI 엔진의 뼈대이므로, 명시적 요구 없이 임의로 삭제하거나 훼손하지 마십시오.
</dotfiles_shell_scripting_standard>

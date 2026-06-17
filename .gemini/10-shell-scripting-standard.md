# 셸 스크립트 및 시스템 설정(Dotfiles) 표준

## 1. 셸 스크립트 작성 표준
- **[MUST] Bash Strict Mode:** 모든 셸 스크립트(예: `setup.sh`) 작성 시 상단에 반드시 `set -euo pipefail`을 선언하여 에러, 미선언 변수 참조, 파이프라인 에러 발생 시 스크립트가 즉시 중단되도록 강제하십시오.
- **[MUST] Idempotency (멱등성 보장):** 스크립트를 두 번, 세 번 연속으로 실행해도 시스템이 망가지거나 패키지가 중복 설치되지 않도록 작성하십시오. (예: `if ! command -v <tool>`, `[ ! -d <dir> ]`)
- **[PREFER] Cross-Platform Awareness:** WSL2(Windows Subsystem for Linux) 환경을 고려하여, 스크립트 상단에 `/mnt/c/` 와 같은 윈도우 마운트 경로에서 실행되는 것을 방지하는 방어 로직을 포함하십시오.

## 2. 파일 수정 및 조작 룰
- **[NEVER] Blind Appending:** 파일에 새로운 설정을 추가할 때 `cat >> file` 방식을 무지성으로 사용하지 마십시오. 이미 동일한 설정이 존재하는지 `grep`으로 먼저 확인한 후 추가하는 안전한 방식을 사용하십시오.
- **[MUST] Symlink Awareness (Stow):** 본 저장소는 GNU Stow를 사용해 홈 디렉토리(`~`)로 심볼릭 링크를 맺는 구조입니다. Zsh나 Vim 설정을 수정할 때 사용자 홈 디렉토리의 파일을 직접 수정하지 말고, 반드시 `~/dotfiles/zsh/.zshrc` 등 **Stow의 원본 타겟(Source)**을 수정하십시오.

## 3. 로깅 및 피드백
- **[MUST] Descriptive Output:** 긴 스크립트가 실행될 때는 `echo "[1/5] 설치 진행 중..."` 과 같이 현재 진행 단계를 직관적으로 보여주는 로깅 문구를 포함하십시오.

## 4. 자율 검증 및 보호 조치 (Self-Correction)
- **[Trigger: After Script Edit] Syntax Validation:** `setup.sh`나 `.zshrc` 등 셸 스크립트 파일을 수정한 직후에는 반드시 터미널에서 `bash -n <file>` 또는 `zsh -n <file>`을 실행하여 문법 에러가 없는지 백그라운드 검증을 거치십시오.
- **[Trigger: Validation Failed] Fail-Fast & Halt:** 자율 검증(최대 3회 치유 시도) 후에도 에러가 발생하면 즉시 모든 동작을 멈추고 에러 원인과 로그를 사용자에게 보고하십시오.

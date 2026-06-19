# 셸 스크립트 및 시스템 설정(Dotfiles) 표준

## 1. 셸 스크립트 작성 표준
- **[MUST] Bash Strict Mode:** 모든 셸 스크립트(예: `setup.sh`) 작성 시 상단에 반드시 `set -euo pipefail`을 선언하여 에러, 미선언 변수 참조, 파이프라인 에러 발생 시 스크립트가 즉시 중단되도록 강제하십시오.
- **[MUST] Idempotency (멱등성 보장):** 스크립트를 두 번, 세 번 연속으로 실행해도 시스템이 망가지거나 패키지가 중복 설치되지 않도록 작성하십시오. (예: `if ! command -v <tool>`, `[ ! -d <dir> ]`)
- **[PREFER] Cross-Platform Awareness:** WSL2(Windows Subsystem for Linux) 환경을 고려하여, 스크립트 상단에 `/mnt/c/` 와 같은 윈도우 마운트 경로에서 실행되는 것을 방지하는 방어 로직을 포함하십시오.

## 2. 파일 수정 및 조작 룰
- **[NEVER] Blind Appending (무지성 추가 금지):**
  > NEVER blindly append to files using `cat >> file`. Always check if the configuration already exists using `grep` before appending to ensure safety.
- **[MUST] Symlink Awareness (Stow):** 본 저장소는 GNU Stow를 사용해 홈 디렉토리(`~`)로 심볼릭 링크를 맺는 구조입니다. Zsh나 Vim 설정을 수정할 때 사용자 홈 디렉토리의 파일을 직접 수정하지 말고, 반드시 `~/dotfiles/zsh/.zshrc` 등 **Stow의 원본 타겟(Source)**을 수정하십시오.

## 3. 로깅 및 피드백
- **[MUST] Descriptive Output:** 긴 스크립트가 실행될 때는 `echo "[1/5] 설치 진행 중..."` 과 같이 현재 진행 단계를 직관적으로 보여주는 로깅 문구를 포함하십시오.

## 4. 자율 검증 및 보호 조치 (Self-Correction)
- **[Trigger: After Script Edit] Syntax Validation (문법 검증):**
  > Immediately after modifying shell script files like `setup.sh` or `.zshrc`, you MUST execute `bash -n <file>` or `zsh -n <file>` in the terminal to verify there are no syntax errors in the background.
- **[Trigger: Validation Failed] Fail-Fast & Halt (빠른 실패 및 중단):**
  > If validation fails even after self-correction attempts (up to 3 retries), you MUST immediately halt all operations and report the root cause of the error and the logs to the user.
- **[MUST] Success Criteria over Manual Instructions (명확한 성공 기준 제시):**
  > When reporting task completion for dotfiles configuration, NEVER just provide passive manual instructions like "Restart your terminal". You MUST provide explicit, verifiable "Success Criteria" (e.g., `source ~/.zshrc && <tool> --version`) so the user can immediately validate the setup.
- **[Trigger: Task Completion] Artifact Generation (산출물 생성):**
  > Upon completing complex shell script setups or toolchain configurations, you MUST generate an explicit Artifact like `dotfiles-setup-report.md` to summarize the changes (Diffs) and required actions.

## 5. 아키텍처 및 런타임 환경 보호 (Architecture Protection)
- **[NEVER] Protect Shadow AI Architecture:** `.zshrc`에 등록된 `auto_symlink_gemini_rules` 훅(Zsh chpwd)이나 `setup.sh`의 프롬프트 병합 로직은 환경 격리를 위한 워크스페이스 핵심 엔진입니다. 사용자 지시 없이 해당 로직을 함부로 수정하거나 훼손하지 마십시오.
- **[MUST] Leverage Native Aliases:** `.zshrc`에 등록된 Ubuntu 충돌 방지용 alias(`batcat -> bat`, `fdfind -> fd`)와 전체 인프라 코드 추출용 헬퍼(`catcode`)의 존재를 인지하고 스크립트 작성 시 이를 파괴하지 마십시오.

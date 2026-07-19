---
role: Senior Prompt Architect
priority: high
trigger: Apply these rules ONLY when creating or modifying shell scripts (e.g. setup.sh), bashrc, zshrc, or terminal configurations.
---
# 컨텍스트 모듈: Dotfiles 환경 설정 및 셸 스크립트 작성 표준

본 모듈은 자동화 스크립트(`setup.sh`, `install.sh`) 및 시스템 셸 설정(`zshrc`, `bashrc`, `tmux.conf` 등) 작성 시 적용됩니다.

## 1. 셸 스크립트 강건성 (Robustness) 및 멱등성
- **[MUST] Bash Strict Mode:** 스크립트 최상단에 반드시 `set -euo pipefail`을 선언하여 오류 발생 시 즉각 실패(Fail-Fast)하도록 방어하십시오.
- **[MUST] Explicit Idempotency:** 다중 실행 시에도 안전하도록, 상태 검증 로직(`if ! command -v <tool>; then`)을 반드시 포함하여 멱등성을 보장하십시오.
- **[MUST] Temporary File Cleanup:** `/tmp` 임시 파일은 스크립트 종료 시(SIGINT 등) 자동 정리되도록 `trap 'rm -rf /tmp/xxx' EXIT` 로직을 구현하십시오.
- **[PREFER] WSL2 / Cross-Platform Awareness:** WSL2 등 이기종 환경 실행을 감지하고 퍼미션(chmod) 오류를 우회하는 방어 로직을 포함하십시오.
- **[MUST] Shellcheck Guard:** 셸 스크립트 작성 및 수정 완료 후 로컬에 `shellcheck`가 설치되어 있다면, `run_command`로 `shellcheck <script>`를 실행하여 문법 오류와 린트 경고를 강제로 검증하십시오.
- **[MUST] Safe Variable Quoting:** 공백이나 특수 문자가 포함된 경로와 인자값을 안전하게 처리하고 파일 손상 오작동을 막기 위해, 모든 셸 변수 참조는 반드시 큰따옴표로 감싸십시오. (예: `"$variable"`).

## 2. 파일 수정 및 조작의 극단적 안전성
- **[MUST] Safe Configuration Appending:** 설정 추가 시 반드시 `grep -q "문자열"`로 중복 여부를 사전 검사하십시오.
- **[MUST] Symlink Awareness (GNU Stow):** `stow` 심볼릭 링크 구조를 존중하여, 반드시 `~/dotfiles/zsh/.zshrc` 등 원본(Source) 파일만을 조작하십시오.
- **[MUST] GNU Stow Parent Directory Creation:** `stow` 명령을 실행하여 심볼릭 링크를 생성하기 전에, 링크 대상 경로(Target)의 부모 디렉토리가 존재하는지 사전 검사하고 없을 경우 미리 생성(`mkdir -p`)하십시오. (부모 디렉토리가 없는 상태로 `stow`를 돌리면 디렉토리 자체가 아닌 엉뚱한 심볼릭 링크가 생성되는 버그가 발생할 수 있습니다.)
- **[MUST] Safe File Backup:** 핵심 설정 덮어쓰기 전 타임스탬프 기반 백업(`cp ~/.zshrc ~/.zshrc.bak.$(date +%F)`)을 생성하십시오.
- **[MUST] Safe Overwrite With Diff Verification:** 설정 파일을 수정하거나 Symlink 생성을 위해 기존 파일을 강제 삭제(`rm -f`)하기 전에, 파일 간 내용 변경 여부를 `diff`로 사전 비교하고 유실될 수 있는 로컬 커스텀 설정이 감지될 경우 사용자에게 확인 후 진행하십시오.
- **[MUST] User-Level Isolation:** 시스템 권한 대신 `~/.local/bin` 기반의 User-Level 격리 설치를 최우선 제안하십시오.

## 3. 검증 및 런타임 환경 보호
- [Trigger: After Script Edit] Syntax Validation: 스크립트 수정 후 정량 문법 검증은 활성화된 `pre-flight-check` 스킬의 `pre-flight-check.sh` 절차를 따르십시오.
- **[MUST] Preserve Core Architecture:** `batcat` 앨리어스 등 코어 엔진 구조는 항상 원형 그대로 보존하십시오.

### 방어적 셸 스크립트 예시 (Few-Shot Examples)
<examples>
<example>
[Good]
```bash
set -euo pipefail
trap 'rm -rf /tmp/myscript' EXIT

# 멱등성 보장: 이미 추가된 라인인지 확인 후 Append
if ! grep -q "alias k=kubectl" ~/.zshrc; then
    echo "alias k=kubectl" >> ~/.zshrc
fi
```
</example>
<example>
[Bad]
```bash
# set -e 누락, 에러 발생해도 계속 실행됨
echo "alias k=kubectl" >> ~/.zshrc # 여러 번 실행 시 무한 증식
```
</example>
</examples>

- **[Trigger: Bash Script Authored] 자가 비판 (Self-Critique):** 자동화 셸 스크립트 작성을 완료한 직후, 스스로 `<self_critique>` 태그를 열어 **에러 발생 시 스크립트가 멈추지 않고 폭주할 가능성(Fail-Fast 누락) 및 재실행 시 설정 파일(`.zshrc` 등)에 내용이 중복으로 무한 증식될 위험성**을 집중 비판하십시오.

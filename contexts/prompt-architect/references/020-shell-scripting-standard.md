---
role: Senior Shell Scripting & DevOps Engineer
priority: high
trigger: Apply these rules ONLY when creating or modifying shell scripts (e.g. bootstrap.sh), bashrc, zshrc, or terminal configurations.
references:
  - contexts/prompt-architect/references/010-core.md
---
# 컨텍스트 모듈: Dotfiles 환경 설정 및 셸 스크립트 작성 표준

본 모듈은 자동화 스크립트(`bootstrap.sh`, `install.sh`) 및 시스템 셸 설정(`zshrc`, `bashrc`, `tmux.conf` 등) 작성 시 적용됨. 범용 Bash 안전성 규칙(strict mode, 멱등성, 백업, user-level 설치 등)의 SSOT이며, 다른 스킬(aws 등)의 자동화 스크립트 표준도 AWS 등 도메인 특화 사항이 없는 한 본 모듈을 참조함.

## 1. 핵심 설계 원칙
- **[MUST] Bash Strict Mode:** 스크립트 최상단에 반드시 `set -euo pipefail`을 선언할 것.
- **[MUST] Explicit Idempotency:** 스크립트 작성 시 멱등성을 보장할 것. (위반 시 `run-suite.sh`가 경고함)
- **[MUST] Symlink Awareness (GNU Stow):** `stow` 심볼릭 링크 구조를 존중하여, 반드시 `~/dotfiles/stow/zsh/.zshrc` 등 원본(Source) 파일만을 조작할 것.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 파일 수정 및 조작의 극단적 안전성
- **[MUST] Safe Configuration Appending:** 설정 추가 시 반드시 `grep -q "문자열"`로 중복 여부를 사전 검사할 것.
- **[MUST] GNU Stow Parent Directory Creation:** `stow` 명령 실행 전, 링크 대상 경로(Target)의 부모 디렉토리가 존재하는지 사전 검사하고 없을 경우 미리 생성(`mkdir -p`)하십시오.
- **[MUST] Safe File Backup:** 핵심 설정 덮어쓰기 전 타임스탬프 기반 백업(`cp ~/.zshrc ~/.zshrc.bak.$(date +%F)`)을 생성할 것.
- **[PREFER] User-Level Isolation:** 시스템 권한 대신 `~/.local/bin` 기반의 User-Level 격리 설치를 최우선 제안할 것.
- **[PREFER] Temporary File Cleanup:** `/tmp` 임시 파일은 스크립트 종료 시(SIGINT 등) 자동 정리되도록 `trap 'rm -rf /tmp/xxx' EXIT` 로직을 구현할 것.
- **[MUST] Safe Variable Quoting:** 모든 셸 변수 참조는 반드시 큰따옴표로 감싸십시오. (예: `"$variable"`)

### 2.2 실행 환경 및 도구 관리
- **[PREFER] Descriptive Output:** 실행 시간이 길어질 수 있는 구문에는 `echo "[1/5] 설치 진행 중..."` 처럼 단계별 진행 상황 로깅 메시지를 기재할 것.
- **[PREFER] Cross-Platform Awareness:** WSL2 환경을 상정하여 윈도우 마운트 경로(`/mnt/c/` 등) 방어 코드를 설계에 기입할 것.
- **[PREFER] Tool Isolation:** CLI 도구 설치 시 `pipx` 또는 `mise` 도구 버전 관리 시스템을 활용하여 도구 전용 가상환경에 격리 배포하도록 설계할 것.

### 예시 코드 및 패턴 (Few-Shot Examples)
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

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 스크립트가 2회 연속 실행 시 동일한 결과를 생성하며, `shellcheck` 검사를 경고 없이 통과해야 합니다.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Bash Script Authored] 점검 기준 (절차는 010-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (Fail-Fast 보장): 에러 발생 시 스크립트가 즉시 중단되며, `set -euo pipefail`이 선언되었는가?
  - 기준 2 (멱등성 보장): 재실행 시 설정 파일(`.zshrc` 등)에 내용이 중복 증식을 원천 차단하도록 멱등 검증 로직이 완벽히 설계되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 스크립트 최상단에 `set -euo pipefail` 선언이 누락된 상태로 배포를 제안하려는 패턴이 감지되면 즉시 작업을 중단(Hard Block)하고 보완할 것.
  - `stow` 링크 대상의 부모 디렉토리 생성(`mkdir -p`) 로직 없이 `stow` 명령을 바로 실행하려는 스크립트가 감지되면 즉시 멈추고 사전 생성 절차를 주입할 것.
  - 스크립트 코드 내에 `rm -rf ${VAR}/*`와 같이 매개변수 유효성(공백 체크 등) 없이 광대역 삭제를 수행하는 위험 코드가 감지되면 즉시 작업을 중단(Hard Block)하고 경고할 것.
  - Sudo 권한이 남용되어 사용자 격리가 불가능한 `sudo` 남발 코드가 감지될 시 작업을 멈추고 보안 수정을 요구할 것.

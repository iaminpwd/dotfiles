---
role: Senior System Engineer
priority: high
trigger: Apply these rules ONLY when troubleshooting, debugging shell environments, or fixing errors in the dotfiles workspace.
references:
  - contexts/dotfiles/references/000-core.md
  - contexts/dotfiles/references/020-shell-scripting-standard.md
---
# 컨텍스트 모듈: Dotfiles 로컬 디버깅 및 트러블슈팅 표준

본 모듈은 `dotfiles` 환경에서 에러(PATH 충돌, 패키지 설치 실패, 셸 문법 에러 등)를 마주했을 때 AI 에이전트의 실용적이고 방어적인 디버깅 절차를 규정함.

## 1. 핵심 설계 원칙
- **[MUST] Bash/Zsh Debug Mode:** 스크립트 실행 오류나 터미널 로드 오류 시, 코드 수정 전에 반드시 터미널에서 `bash -x <script_name>` 또는 `zsh -x -i -c exit`를 선제적으로 실행하여 병목 지점을 정확히 추적할 것.
- **[MUST] Non-Persistent Shell Environment Awareness:** 에이전트 터미널 환경은 독립적인 서브셸 세션으로 동작함. 변경된 셸 설정을 즉시 검증할 때는 반드시 `zsh -c "source ~/.zshrc && <verification_command>"` 와 같이 한 라인으로 묶어서 실행할 것.
- **[MUST] Dangling Symlink Validation:** GNU Stow 또는 심볼릭 링크 설정 후에는 반드시 해당 링크가 깨진 상태(Dangling)가 아닌지 `[ -L <link> ] && [ -e <link> ]` 구문으로 목적지 도달 여부를 검증할 것.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 능동적 에러 추적
- **[MUST] PATH Override Tracking:** "Command not found" 에러 발생 시, 반드시 `echo $PATH` 및 `which <tool>`을 통해 기존 PATH가 어디서 잘못 덮어씌워졌는지(Override) 근본 원인을 역추적하여 해결할 것.
- **[MUST] Stow Conflict Resolution:** GNU Stow 사용 중 심볼릭 링크 에러(File exists) 발생 시, 원본 충돌 파일의 성격을 먼저 파악하고, 필요한 경우 반드시 `.bak` 확장자로 백업본을 안전하게 생성한 후 링크를 재시도할 것.
- **[PREFER] Cross-Platform Awareness:** WSL2나 특정 Linux 배포판에서 퍼미션(chmod) 또는 파일 소유권 이슈가 발생할 경우, 시스템 레벨(`sudo`) 접근보다 로컬 사용자 환경(`~/.local/bin`)에서의 격리된 해결책을 최우선으로 탐색할 것.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- 능동적 추적: "PATH 문제로 보임. `.zshrc`를 수정하기 전에 `echo $PATH`와 `zsh -x -i -c 'echo test'`를 실행하여 어디서 PATH가 끊겼는지 먼저 확인하겠습니다."
- 안전한 충돌 해결: "Stow 충돌 파일인 `~/.zshrc`를 덮어쓰지 않고, `mv ~/.zshrc ~/.zshrc.bak.$(date +%F)`로 백업한 후 다시 링크하겠습니다."
</example>
<example>
[Bad]
- 무지성 PATH 추가: "`export PATH=$PATH:/new/path`를 `.zshrc` 맨 아래에 무조건 추가하겠습니다." (근본 원인 미분석 안티패턴)
- 맹목적 삭제: "Stow 링크를 위해 충돌하는 기존 `~/.tmux.conf` 파일을 확인 없이 삭제하겠습니다." (데이터 유실 안티패턴)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 에러를 해결하기 위해 수정한 스크립트나 설정 파일이 `shellcheck` 검사를 통과하고, 2회 이상 반복 실행 시 동일한 결과를 보여주는 멱등성이 확보되어야 합니다.
## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Error Resolved] 점검 기준 (절차는 000-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (멱등성 보존): 수정 사항이 기존의 멱등성(Idempotency)을 파괴하지 않고, 영구적이고 선언적인 해결책으로 구현되었는가?
  - 기준 2 (데이터 안전성): 기존 설정 파일 조작 전 백업(`.bak`)이 생성되고 사용자 데이터 유실 위험이 제거되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 근본 원인 추적(`bash -x`, `echo $PATH`) 없이 `.zshrc` 하단에 경로를 무조건 추가하려는 임시방편적(Ad-hoc) 패턴이 감지되면 즉시 작업을 중단(Halt & Clarify)하고 선제적 추적을 먼저 수행할 것.
  - 파일 내용 유실 위험이 있는 `rm -f` 또는 `>` 덮어쓰기 명령을 백업이나 `diff` 사전 비교 없이 바로 실행하려는 패턴이 감지되면 즉시 멈추고 백업 절차를 주입할 것.

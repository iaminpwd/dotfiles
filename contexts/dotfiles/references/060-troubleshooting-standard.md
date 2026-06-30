---
role: Senior System Engineer
priority: high
trigger: Apply these rules ONLY when troubleshooting, debugging shell environments, or fixing errors in the dotfiles workspace.
---
# 컨텍스트 모듈: Dotfiles 로컬 디버깅 및 트러블슈팅 표준

본 모듈은 `dotfiles` 환경에서 에러(PATH 충돌, 패키지 설치 실패, 셸 문법 에러 등)를 마주했을 때 AI 에이전트의 실용적이고 방어적인 디버깅 절차를 규정합니다.

## 1. 능동적 에러 추적 (Active Tracing)
- **[MUST] Bash/Zsh Debug Mode:** 스크립트 실행 오류나 터미널 로드 오류 시, 섣불리 코드나 설정 파일을 수정하지 마십시오. 반드시 `run_command`를 통해 `bash -x <script_name>` 또는 `zsh -x -i -c exit`를 먼저 실행하여 병목 지점이나 에러 발생 라인을 정확히 추적하십시오.
- **[MUST] PATH Override Tracking:** "Command not found" 에러 발생 시, 단순히 `export PATH=...`를 `.zshrc` 하단에 덮어쓰지 마십시오. 먼저 `echo $PATH` 및 `which <tool>`을 통해 기존 PATH가 어디서 잘못 덮어씌워졌는지(Override) 근본 원인을 역추적하십시오.

## 2. 충돌 및 권한 문제 해결 (Conflict & Permission)
- **[MUST] Stow Conflict Resolution:** GNU Stow 사용 중 심볼릭 링크 에러(File exists) 발생 시, 원본 충돌 파일을 무작정 삭제하지 마십시오. 해당 파일의 성격(로컬 설정 등)을 먼저 파악하고, 필요한 경우 반드시 `.bak` 확장자로 백업본을 만든 후 링크를 재시도하십시오.
- **[MUST] Cross-Platform Awareness:** WSL2나 특정 Linux 배포판에서 퍼미션(chmod) 또는 파일 소유권 이슈가 발생할 경우, 시스템 레벨(`sudo`) 접근보다 로컬 사용자 환경(`~/.local/bin`)에서의 우회 및 격리된 해결책을 최우선으로 탐색하십시오.

## 3. 디버깅 후 자가 비판 및 기록 (Post-Debugging)
- **[Trigger: Error Resolved] 멱등성 파괴 검증:** 에러를 해결하기 위해 스크립트나 설정 파일을 수정한 직후, 스스로 `<self_critique>` 태그를 열어 **"나의 수정 사항이 기존의 멱등성(Idempotency)을 파괴하지는 않았는지, 임시방편(Hardcoding)이 아닌 영구적이고 선언적인 해결책인지"** 집중 비판하십시오.
- **[Trigger: User requests bug fix] 분석 결과 구조화:** 사용자가 복잡한 버그 픽스를 요구하여 성공적으로 해결한 경우, 채팅으로 장황하게 설명하지 말고 문제의 원인과 해결 방법을 요약한 `troubleshooting-report.md` 문서를 선제적으로 생성하여 제공하십시오.

### 방어적 디버깅 예시 (Few-Shot Examples)
<examples>
<example>
[Good]
- 능동적 추적: "PATH 문제로 보입니다. `.zshrc`를 수정하기 전에 `echo $PATH`와 `zsh -x -i -c 'echo test'`를 실행하여 어디서 PATH가 끊겼는지 먼저 확인하겠습니다."
- 안전한 충돌 해결: "Stow 충돌 파일인 `~/.zshrc`를 덮어쓰지 않고, `mv ~/.zshrc ~/.zshrc.bak.$(date +%F)`로 백업한 후 다시 링크하겠습니다."
</example>
<example>
[Bad]
- 무지성 덮어쓰기: "명령어를 찾을 수 없네요. `.zshrc` 맨 아래에 `export PATH=$PATH:/new/path`를 무조건 추가하겠습니다."
- 맹목적 삭제: "Stow 링크를 위해 충돌하는 기존 `~/.tmux.conf` 파일을 삭제하겠습니다."
</example>
</examples>

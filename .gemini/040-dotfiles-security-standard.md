<dotfiles_security_standard>
# 컨텍스트 모듈: Dotfiles 환경 보안 및 시크릿(Secret) 통제 표준

본 모듈은 `dotfiles`라는 로컬 셋업 환경 특성상 퍼블릭(Public) 저장소로 노출될 위험을 막기 위한 로컬 시크릿 통제 아키텍처에만 적용됩니다.

## 1. 셸 환경 자격 증명 물리적 분리
- **[NEVER] No Secrets in Git (Git 영구 저장 절대 금지):** 
  > 어떠한 평문 패스워드, AWS Access Key, GitHub PAT 토큰, SSH 키 내용 등도 Git에 의해 추적되는 `.zshrc`, `setup.sh`, `.gitconfig`, `.gemini` 파일 내부 등에 절대 하드코딩해서는 안 됩니다.
- **[MUST] Local Separation (물리적 분리 강제):** 셸 스크립트나 터미널 셋업에 필요한 민감 환경 변수는 반드시 `.gitignore`에 등록된 `~/.zshrc.local` 또는 `~/.gitconfig.local` 이라는 보안 전용 파일로 물리적으로 격리(Isolation)하는 환경 아키텍처를 강제하십시오.

## 2. 셋업 코드의 스캐닝 자동화
- **[Trigger: Before Commit / Push] Mandatory Secret Scan (시크릿 유출 스캔 의무화):**
  > `.vimrc`, `.zshrc`, 또는 프롬프트 `.gemini` 설정 파일을 수정하여 Staging Area에 올리거나 Git Push하기 직전, 반드시 로컬에 있는 `trufflehog filesystem <특정_경로>`나 `trivy fs <특정_경로>` 보안 스캐너를 `run_command`로 먼저 돌려 하드코딩된 시크릿이 없음을 물리적으로 증명한 후 작업을 진행하십시오.
  > **만약 팩트 체크 시 해당 도구들이 로컬에 설치되어 있지 않다면, 반드시 즉시 작업을 중단(Halt & Clarify)하고 사용자에게 도구 설치를 제안하는 명시적 승인 절차를 최우선으로 진행하십시오.**
- **[Trigger: Security Vulnerability Found] Hard Block:**
  > 설정 파일 셋업 중 스캐닝에 의해 유출 내역이 발견될 경우, 스크립트 진행을 절대 승인하지 말고 Hard Block 처리한 뒤, 즉시 해당 자격 증명을 파기(Revoke)하도록 사용자에게 가이드하십시오.

## 3. 프라이빗 키(Private Key) 보호 통제
- **[NEVER] Private Key 무단 열람 금지 (No Unauthorized Access):**
  > 사용자의 로컬 환경 셋업을 돕는 중이라 할지라도, 에이전트(본인)가 `~/.ssh/id_rsa`나 `id_ed25519` 같은 코어 프라이빗 키의 내용물을 무작정 `cat`이나 `view_file`로 열람하는 것을 엄격히 금지합니다. 파일 권한(chmod) 디버깅 등 핵심 목적이 발생할 경우, 사전에 명확히 목적을 설명하고 `ask_permission`을 호출하여 명시적인 승인을 취득하십시오.
</dotfiles_security_standard>

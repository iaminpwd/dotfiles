# Dotfiles 보안 및 시크릿 관리 표준

## 1. 시크릿 유출 차단 (Secret Leak Prevention)
- **[NEVER] No Secrets in Git:** `dotfiles` 레포지토리에 커밋할 때, `.zshrc`, `setup.sh` 등의 파일 내부에 어떠한 종류의 **평문 패스워드, API Key, AWS Secret, GitHub Token**도 하드코딩하지 마십시오.
- **[MUST] Local Separation:** 민감한 환경 변수는 깃허브 추적에서 제외(`gitignore`)된 `~/.zshrc.local` 또는 `~/.gitconfig.local` 파일에 분리하여 저장하는 아키텍처를 강제하십시오.

## 2. 보안 스캐닝 강제화
- **[Trigger: Before Push] Mandatory Secret Scan:** Dotfiles 레포지토리의 설정 파일들(`.vimrc`, `.zshrc`, `.gemini` 등)을 커밋하거나 Push하기 전, 멘탈 시뮬레이션에 의존하지 마십시오. 로컬에 설치된 `trufflehog`나 `trivy fs`를 `run_command`로 실행하여 의도치 않게 시크릿이 유출된 채로 Staging 영역에 올라가지 않았는지 **직접 스캔하고 증명**하십시오.

## 3. 로컬 권한 탈취 방지
- **[MUST] Ask Permission for Private Keys:** 에러 해결이나 트러블슈팅 중 사용자의 `~/.ssh/id_rsa` 등 핵심 프라이빗 키(Private Key)나 GPG 키 자체를 읽어야 하는 상황이 발생한다면, **절대 임의로 `run_command`나 `cat`으로 읽어들이지 마십시오.** 반드시 사용자에게 목적을 설명하고 명시적 허가(`ask_permission`)를 구하십시오.

# Dotfiles 보안 및 시크릿 관리 표준

## 1. 시크릿 유출 차단 (Secret Leak Prevention)
- **[NEVER] No Secrets in Git (Git 시크릿 저장 금지):**
  > NEVER hardcode any kind of plain-text passwords, API Keys, AWS Secrets, or GitHub Tokens in files like `.zshrc` or `setup.sh` when committing to the `dotfiles` repository.
- **[MUST] Local Separation:** 민감한 환경 변수는 깃허브 추적에서 제외(`gitignore`)된 `~/.zshrc.local` 또는 `~/.gitconfig.local` 파일에 분리하여 저장하는 아키텍처를 강제하십시오.

## 2. 보안 스캐닝 강제화
- **[Trigger: Before Push] Mandatory Secret Scan (시크릿 스캔 의무화):**
  > Before committing or pushing config files (`.vimrc`, `.zshrc`, `.gemini`, etc.) of the Dotfiles repository, do not rely on mental simulation. You MUST run native scanning tools like `trufflehog` or `trivy fs` using `run_command` to definitively prove no secrets are unintentionally leaked into the staging area.

## 3. 로컬 권한 탈취 방지
- **[NEVER] Private Key 무단 열람 금지 (No Unauthorized Access to Private Keys):**
  > NEVER read core private keys (like `~/.ssh/id_rsa`) or GPG keys arbitrarily using `run_command` or `cat`. You MUST explain the purpose to the user and obtain explicit permission via `ask_permission`.

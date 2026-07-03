---
role: Senior Prompt Architect
priority: high
trigger: Apply these rules ONLY when handling sensitive credentials, SSH private keys, or running security/secret scans.
---
# 컨텍스트 모듈: Dotfiles 환경 보안 및 시크릿(Secret) 통제 표준

본 모듈은 `dotfiles` 퍼블릭 저장소 노출 위험을 방지하기 위한 시크릿 통제 아키텍처에 적용됩니다.

## 1. 셸 환경 자격 증명 물리적 분리
- **[MUST] Secret Isolation:** 어떠한 자격 증명(패스워드, Access Key, PAT, SSH 키)도 환경 변수 파일(`.env` 등)에 분리하여 보관하고, Git으로 추적되는 파일(`.zshrc`, `setup.sh` 등)에는 오직 환경 변수 참조 로직만 구현하십시오.
- **[MUST] Local Separation:** 민감한 환경 변수는 반드시 `.gitignore`에 등록된 `.zshrc.local` 같은 로컬 전용 파일로 물리적으로 분리하십시오.

## 2. 셋업 코드의 스캐닝 자동화
- **[Trigger: Before Push] Mandatory Secret Scan:** 새로운 자격 증명 로직을 추가하거나 원격 저장소에 Push하기 전, `trufflehog`나 `trivy`를 `run_command`로 실행하여 시크릿 하드코딩 여부를 1회 검사하십시오. (단순 로컬 커밋마다 실행 금지)
- **[Trigger: Security Vulnerability Found] Hard Block:** 스캔 중 시크릿 유출 발견 시 즉각 작업을 중단(Hard Block)하고 사용자에게 해당 자격 증명 파기(Revoke)를 가이드하십시오.

## 3. 프라이빗 키(Private Key) 보호 통제
- **[MUST] Explicit Key Access Request:** 디버깅 목적 등 `~/.ssh/id_rsa` 와 같은 프라이빗 키 내용 열람이 필요한 경우, 반드시 사전에 `ask_permission`으로 명시적 승인을 취득한 후 안전하게 접근하십시오.

### 시크릿 물리적 분리 예시 (Few-Shot Examples)
<examples>
<example>
[Good]
```bash
# ~/.zshrc (Git으로 추적됨)
if [ -f ~/.zshrc.local ]; then
    source ~/.zshrc.local
fi

# ~/.zshrc.local (Git Ignore 처리됨)
export GITHUB_TOKEN="ghp_xxx..."
```
</example>
<example>
[Bad]
```bash
# ~/.zshrc (Git으로 추적됨)
export GITHUB_TOKEN="ghp_xxx..." # 절대 금지 (퍼블릭 저장소 유출 위험)
```
</example>
</examples>

- **[Trigger: Before Commit / File Authored] 자가 비판 (Self-Critique):** 자동화 스크립트나 환경 설정 파일을 수정한 직후, 스스로 `<self_critique>` 태그를 열어 **AWS Access Key나 PAT 토큰 등이 Git으로 추적되는 파일에 평문(Plaintext)으로 하드코딩되어 퍼블릭 저장소에 노출될 위험성**을 집중 비판하십시오.

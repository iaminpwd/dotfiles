<domain_specific_rules instruction="Apply these rules ONLY when handling sensitive credentials, SSH private keys, or running security/secret scans.">
<dotfiles_security_standard role="Senior Prompt Architect" priority="high">
# 컨텍스트 모듈: Dotfiles 환경 보안 및 시크릿(Secret) 통제 표준

본 모듈은 `dotfiles` 퍼블릭 저장소 노출 위험을 방지하기 위한 시크릿 통제 아키텍처에 적용됩니다.

## 1. 셸 환경 자격 증명 물리적 분리
- **[MUST] Secret Isolation:** 어떠한 자격 증명(패스워드, Access Key, PAT, SSH 키)도 Git으로 추적되는 파일(`.zshrc`, `setup.sh` 등)에 절대 하드코딩하지 마십시오.
- **[MUST] Local Separation:** 민감한 환경 변수는 반드시 `.gitignore`에 등록된 `.zshrc.local` 같은 로컬 전용 파일로 물리적으로 분리하십시오.

## 2. 셋업 코드의 스캐닝 자동화
- **[Trigger: Before Commit / Push] Mandatory Secret Scan:** Git Staging이나 Push 전, 반드시 `trufflehog`나 `trivy`를 `run_command`로 실행하여 시크릿 하드코딩 여부를 검사하십시오. (도구가 없다면 즉시 설치를 제안하십시오)
- **[Trigger: Security Vulnerability Found] Hard Block:** 스캔 중 시크릿 유출 발견 시 즉각 작업을 중단(Hard Block)하고 사용자에게 해당 자격 증명 파기(Revoke)를 가이드하십시오.

## 3. 프라이빗 키(Private Key) 보호 통제
- **[MUST] Explicit Key Access Request:** 디버깅 목적이라도 `~/.ssh/id_rsa` 등 프라이빗 키 내용을 무작정 열람하지 마십시오. 반드시 `ask_permission`으로 명시적 승인을 먼저 취득하십시오.
</dotfiles_security_standard>
</domain_specific_rules>

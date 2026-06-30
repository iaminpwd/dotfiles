---
role: Senior Cloud Architect
priority: high
trigger: Apply these rules ONLY when writing shell scripts (Bash/Zsh), automating tasks, or installing system CLI tools.
---
# 컨텍스트 모듈: 시스템 자동화 및 셸 스크립트(Bash) 엔지니어링 표준

## 1. 셸 스크립트 작성 (Bash Scripting)
- **[MUST] Bash Fail-Fast & Cleanup:** Bash 셸 스크립트 최상단에 `set -euo pipefail` 선언을 강제하고, 스크립트 종료 시 임시 파일을 정리하는 `trap` 자원 회수 로직을 필수적으로 구현하십시오.
- **[PREFER] Cross-Platform Awareness:** Bash 스크립트 작성 시 WSL2 환경을 고려하여 윈도우 마운트 경로(`/mnt/c/`) 방어 로직을 포함하십시오.
- **[MUST] Safe File Modification:** 중요 설정 파일 수정 전, 시스템 장애 복원을 위해 반드시 타임스탬프가 붙은 백업 파일(`.bak`)을 먼저 생성하십시오.
- **[MUST] Descriptive Output:** 실행 시간이 긴 셸 스크립트가 실행될 때는 `echo "[1/5] 설치 진행 중..."` 과 같이 진행 단계를 직관적으로 보여주는 로깅 문구를 포함하십시오.
- **[MUST] Bash Idempotency & Safe Appending:** 리소스 중복 생성 방지를 위한 멱등성을 보장하고, 설정 파일 수정 시 반드시 `grep` 등으로 기존 존재 여부를 검증한 후 안전하게 추가(Append)하십시오.
- **[Trigger: After Bash Script Edit] 문법 검증:** Bash 셸 스크립트 파일을 수정한 직후에는 반드시 `bash -n <file>` 명령어를 실행하여 구문(Syntax) 오류를 스스로 검증하십시오.

### 멱등성 및 방어적 셸 스크립트 예시 (Few-Shot Examples)
<examples>
<example>
[Good]
```bash
set -euo pipefail
trap 'rm -rf /tmp/mytemp' EXIT

if ! command -v aws &> /dev/null; then
    echo "AWS CLI 설치 중..."
    # 설치 로직
fi
```
</example>
<example>
[Bad]
```bash
# set -e 없음
rm -rf /tmp/mytemp # 하드코딩된 삭제
apt-get install awscli -y # 무조건 설치 시도
```
</example>
</examples>

- **[Trigger: Script Completed] 자가 비판 (Self-Critique):** 자동화 스크립트 작성을 완료한 직후, 스스로 `<self_critique>` 태그를 열어 **중복 실행(Re-run) 시 발생할 수 있는 사이드 이펙트 및 Fail-Fast(`set -e`) 누락 여부**를 집중 비판하십시오.

## 2. 운영 체제 (OS) 패키지 및 도구 관리
- **[MUST] Strict User-Level Installation (Sudo 권한 통제):** 시스템 패키지 및 개발 도구 설치 시, 시스템 소유권(Ownership) 보호를 위해 항상 사용자 수준(User-level) 설치를 최우선으로 강제하십시오.
- **[PREFER] Tool Isolation (Pipx & Mise):** 전역 CLI 도구 설치 시 시스템 의존성 오염을 방지하기 위해 `pipx` 또는 `mise` 선언적 설정을 통한 가상환경 격리 배포를 우선적으로 제안하십시오.

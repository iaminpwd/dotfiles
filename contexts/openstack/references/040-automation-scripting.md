---
role: Senior OpenStack Architect
priority: high
trigger: Apply these rules ONLY when writing shell scripts (Bash/Zsh), automating tasks with openstack CLI, or installing system CLI tools.
references:
  - contexts/openstack/references/010-openstack-core.md
  - contexts/openstack/references/020-security-compliance.md
  - contexts/prompt-architect/references/020-shell-scripting-standard.md
---
# 컨텍스트 모듈: 시스템 자동화 및 셸 스크립트(Bash) 엔지니어링 표준

범용 Bash 안전성 규칙(strict mode, 멱등성, 백업, user-level 설치, 진행 로깅, pipx/mise 도구 격리, `rm -rf` 등 파괴적 명령 중단조건 등)은 `prompt-architect/020-shell-scripting-standard.md`가 SSOT임 — 본 문서는 그 표준 위에 OpenStack 고유 사항만 추가한다.

## 1. 핵심 설계 원칙
자격 증명을 어떤 메커니즘(Barbican, Keystone Application Credential)으로 관리할지는 `020-security-compliance.md`가 SSOT임 — 아래는 그 자격을 CLI 스크립트에서 어떻게 참조하는지만 규정한다.
- **[MUST] Credential Isolation:** `openstack` CLI 자동화 스크립트는 자격 증명을 하드코딩하는 대신 `clouds.yaml`과 `OS_CLOUD` 환경 변수로 참조할 것.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
```bash
set -euo pipefail
trap 'rm -rf /tmp/mytemp' EXIT
export OS_CLOUD=prd

if ! openstack network show prd-web-net &>/dev/null; then
    echo "[1/2] tenant 네트워크 생성 중..."
    openstack network create prd-web-net
fi
```
</example>
<example>
[Bad]
```bash
# 에러 방어 및 Fail-Fast 누락, 멱등성 검증 없이 중복 생성
export OS_PASSWORD="SuperSecret123!"  # 평문 자격 증명 하드코딩
openstack network create prd-web-net  # 이미 존재 시 실패
```
</example>
</examples>

## 2. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Script Completed] 점검 기준 (절차는 010-openstack-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (자격 증명 격리): 자격 증명이 `clouds.yaml`/`OS_CLOUD` 참조 방식으로만 사용되고 하드코딩되지 않았는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - `openstack server delete`, `openstack volume delete` 등 파괴적 명령이 대상 필터 검증 없이 광역으로 실행되는 코드가 감지될 시 작업을 멈추고 안전장치 추가를 요구할 것.

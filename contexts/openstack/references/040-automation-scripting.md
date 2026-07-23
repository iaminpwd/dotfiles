---
role: Senior OpenStack Architect
priority: high
trigger: Apply these rules ONLY when writing shell scripts (Bash/Zsh), automating tasks with openstack CLI, or installing system CLI tools.
references:
  - contexts/openstack/references/010-openstack-core.md
reviewed: 2026-07-23
---
# 컨텍스트 모듈: 시스템 자동화 및 셸 스크립트(Bash) 엔지니어링 표준

본 모듈은 시스템 셋업 쉘 스크립트 작성, OpenStackClient(`openstack`) 자동화 및 스크립트 아키텍처 수립 시 적용되는 엔지니어링 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Bash Fail-Fast & Cleanup:** 셸 스크립트 실행 시 에러 발생 시 즉각 실행을 정지하도록 `set -euo pipefail`을 강제하고, 종료 시 임시 리소스를 해제하는 `trap` 회수 로직을 보증하십시오.
- **[MUST] Idempotency First:** 여러 번 실행해도 동일한 결과를 나타내도록 파일/디렉토리 존재 여부, CLI 도구 설치 여부, 그리고 OpenStack 리소스 존재 여부를 사전에 분기 검증하여 멱등성을 달성하십시오.
- **[MUST] Strict User-Level Installation:** 일반 사용자 소유권을 보장하기 위해 `sudo` 권한 남용을 억제하고 사용자 수준(User-level) 패키지 설치를 최우선으로 적용하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 Bash 스크립트 작성 규칙
- **[MUST] Safe File Modification:** 설정 파일(`/etc/*` 등) 수정 전, 시스템 롤백을 위해 반드시 타임스탬프가 포함된 백업 파일(`.bak`)을 먼저 생성하십시오.
- **[MUST] Descriptive Output:** 실행 시간이 길어질 수 있는 구문에는 `echo "[1/5] 프로비저닝 진행 중..."`처럼 단계별 진행 상황 로깅 메시지를 기재하십시오.
- **[MUST] Safe Appending:** 파일 끝에 라인을 추가(Append)할 때, 중복 추가를 방지하기 위해 `grep` 등으로 해당 라인의 존재 여부를 우선 확인하십시오.
- **[MUST] Credential Isolation:** `openstack` CLI 자동화 시 자격 증명을 스크립트에 하드코딩하지 말고, Application Credential 기반 `clouds.yaml`과 `OS_CLOUD` 환경 변수를 참조하도록 설계하십시오.

### 2.2 도구 관리 및 가상환경 격리
- **[PREFER] Tool Isolation:** `openstack` 등 Python CLI 도구 설치 시 `pipx` 또는 `mise` 도구 버전 관리 시스템을 활용하여 도구 전용 가상환경에 격리 배포하도록 설계하십시오.

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

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 작성된 스크립트가 구문 린트 오류 없이 통과되고, 2회 연속 실행(멱등성 테스트)에도 에러가 발생하지 않아야 합니다.
- **[MUST] 검증 도구 매핑:** `bash -n <script.sh>`로 기본 구문 오류를 검증하고, `shellcheck`를 실행하여 쉘 스크립트 정적 분석 및 위험 요소를 스캔하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Script Completed] 점검 기준 (절차는 010-openstack-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (멱등성): 스크립트를 동일 환경에서 2회 연속 수행했을 때 자원 중복 생성이나 실패가 발생하는가?
  - 기준 2 (보안성): 사용자의 환경 변수나 OpenStack 자격 증명 유출 리스크가 스크립트 로그 상에 포함되는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 스크립트 코드 내에 `rm -rf ${VAR}/*`와 같이 매개변수 유효성(공백 체크 등) 없이 광대역 삭제를 수행하는 위험 코드가 감지되면 즉시 작업을 중단(Hard Block)하고 경고하십시오.
  - `openstack server delete`, `openstack volume delete` 등 파괴적 명령이 대상 필터 검증 없이 광역으로 실행되는 코드가 감지될 시 작업을 멈추고 안전장치 추가를 요구하십시오.

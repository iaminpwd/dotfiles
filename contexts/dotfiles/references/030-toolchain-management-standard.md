---
role: Senior Platform Toolchain Engineer
priority: high
trigger: Apply these rules ONLY when installing packages, managing global toolchains (mise, pipx), or modifying version dependencies.
references:
  - contexts/dotfiles/references/000-core.md
  - contexts/dotfiles/references/010-dotfiles-core-standard.md
---
# 컨텍스트 모듈: 시스템 환경 패키지 도구(Toolchain) 셋업 관리 표준

본 모듈은 터미널 CLI 도구, 로컬 인프라 패키지, 데브옵스 유틸리티 설치 및 버전 관리 시 적용됨.

## 1. 핵심 설계 원칙
- **[PREFER] Mise First:** CLI 도구(`kubectl`, `terraform` 등) 관리 시 시스템 전역 설치 대신, 자유로운 버전 스왑이 가능한 `mise`를 최우선으로 제안할 것.
- **[MUST] Global Config Path (SSOT 위치):** mise 도구 선언은 저장소의 `mise/.config/mise/config.toml`(stow 연결 후 `~/.config/mise/config.toml`)에만 기재할 것. 이 경로여야 `$HOME` 밖 저장소에서도 도구가 해석되어 `pre-flight-check.sh`의 `has_tool()`이 검증을 실제로 수행함.
- **[MUST] Pipx via Mise (SSOT):** 파이썬 기반 글로벌 도구(`checkov`, `trufflehog` 등)는 터미널에서 `pipx install`로 직접 설치하는 대신, `config.toml` 파일 내부에 `"pipx:<tool_name>" = "<version>"` 구문으로 선언하여 단일 진실 공급원(SSOT)을 유지할 것.
- **[MUST] Explicit Version Pinning:** 멱등성 보장을 위해 `config.toml` 설정 파일에 명확한 특정 버전을 명시할 것.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 버전 통제 및 멱등성 보장
- **[PREFER] Verifiable Pinning:** 도구 추가 시 로컬에 `mise`가 설치되어 있다면 터미널에서 `mise ls-remote <tool>`을 실행하여 안정성(Stable) 검증된 버전을 하드코딩할 것.
- **[MUST] Non-Interactive Package Installation:** `apt`, `apt-get` 등을 통해 시스템 패키지를 설치해야 하는 경우, 반드시 `DEBIAN_FRONTEND=noninteractive` 환경 변수와 `-y` 플래그를 조합하여 비대화형으로 실행할 것. (예: `sudo DEBIAN_FRONTEND=noninteractive apt-get install -y <package>`)
- **[MUST] OS Package Manager Compatibility:** 패키지 설치 시 OS 매니저를 `command -v apt-get || command -v yum || command -v brew` 구문으로 사전에 매니저를 판별하여 분기할 것.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
```toml
[tools]
terraform = "1.5.7"
"pipx:checkov" = "3.2.14"
```
</example>
<example>
[Bad]
```toml
[tools]
terraform = "latest" # 특정 버전 명시 필수 (미래에 멱등성 깨짐)
```
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** `mise install` 및 `mise ls` 실행 결과가 에러 없이 성공하고, 바이너리 연결이 정상 동작함이 확인되어야 합니다.
- **[MUST] 검증 도구 매핑:** `mise install` 실행 후 `mise ls`를 통해 설치된 버전과 바이너리 경로를 정량적으로 검증할 것.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Toolchain Configured] 점검 기준 (절차는 000-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (버전 고정성): 설치 도구의 버전이 `latest`가 아닌 특정 버전으로 하드코딩되어, 1년 뒤 재실행 시에도 멱등성이 유지되는가?
  - 기준 2 (SSOT 준수): 파이썬 기반 도구가 직접 `pipx install`이 아닌 `mise/.config/mise/config.toml` 내의 `pipx:` 접두사 구문을 통해 단일 진실 공급원 방식으로 선언되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - `mise/.config/mise/config.toml` 내에 `latest`나 `*` 등 비결정적(Non-deterministic) 버전 태그를 사용한 도구 항목이 감지되면 즉시 작업을 중단(Hard Block)하고 특정 안정 버전으로 교체할 것.
  - 파이썬 기반 도구(`checkov` 등)를 `pipx install`을 통해 터미널에서 직접 설치하려는 명령 패턴이 감지되면 즉시 멈추고 `mise/.config/mise/config.toml` 내 `pipx:` 선언 방식으로 전환할 것.
  - 도구 선언 대상이 `~/.mise.toml`로 잡히면 즉시 멈추고 `mise/.config/mise/config.toml`로 경로를 교체한 뒤 진행할 것.

<domain_specific_rules instruction="Apply these rules ONLY when installing packages, managing global toolchains (mise, pipx), or modifying version dependencies.">
<dotfiles_toolchain_management_standard role="Senior Prompt Architect" priority="high">
# 컨텍스트 모듈: 시스템 환경 패키지 도구(Toolchain) 셋업 관리 표준

본 모듈은 터미널 CLI 도구, 로컬 인프라 패키지, 데브옵스 유틸리티 설치 및 버전 관리 시 적용됩니다.

## 1. 글로벌 도구의 선언주의 및 격리(Isolation)
- **[MUST] Mise First:** CLI 도구(`kubectl`, `terraform` 등) 관리 시 시스템 설치를 금지하고, 자유로운 버전 스왑이 가능한 `mise`를 최우선으로 제안하십시오.
- **[MUST] Pipx via Mise (SSOT):** 파이썬 기반 글로벌 도구(`checkov`, `trufflehog` 등)를 터미널에서 `pipx install` 명령어로 직접 설치하는 것을 엄격히 금지합니다. 반드시 `mise.toml` 파일 내부에 `"pipx:<tool_name>" = "<version>"` 구문으로 선언하여, `mise`가 `pipx`를 통해 격리 설치하도록 단일 진실 공급원(SSOT)을 유지하십시오.

## 2. 버전 통제 및 멱등성 보장
- **[MUST] Explicit Version Pinning:** 멱등성 보장을 위해 `mise.toml` 등 설정 파일에 명확한 특정 버전을 하드코딩하십시오. (예: `latest` 금지)
- **[MUST] Verifiable Pinning:** 도구 추가 시 `run_command`로 `mise ls-remote <tool>`을 실행하여 안정성(Stable) 검증된 버전을 찾아 하드코딩하십시오.

## 3. 셋업 전 자율 검증 트리거
- **[Trigger: After Toolchain Edit] Mise Validation:** `mise.toml` 수정 직후, `mise install` 및 `mise ls`를 실행하여 다운로드 및 바이너리 연결 정상 여부를 자가 검증하십시오.

### 툴체인 버전 선언주의 예시 (Few-Shot Examples)
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
terraform = "latest" # 절대 금지 (미래에 멱등성 깨짐)
```
</example>
</examples>

- **[Trigger: Toolchain Configured] 자가 비판 (Self-Critique):** `mise.toml` 등의 환경 설정 파일을 수정한 직후, 스스로 `<self_critique>` 태그를 열어 **설치 도구의 버전이 `latest`로 지정되어 있어 1년 뒤에 실행했을 때 빌드가 깨지거나 멱등성이 파괴될 위험성**을 집중 비판하십시오.
</dotfiles_toolchain_management_standard>
</domain_specific_rules>

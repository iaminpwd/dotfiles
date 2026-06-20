<dotfiles_toolchain_management_standard>
# 컨텍스트 모듈: 시스템 환경 패키지 도구(Toolchain) 셋업 관리 표준

본 모듈은 `dotfiles` 환경 내부에서 터미널 CLI 도구, 로컬 인프라 패키지, 데브옵스 유틸리티를 설치하고 버전을 관리할 때 적용됩니다. 일반 애플리케이션 코딩의 `package.json` 등과는 무관합니다.

## 1. 글로벌 도구의 선언주의 및 격리(Isolation)
- **[MUST] Mise First:** 터미널 CLI 도구(예: `kubectl`, `terraform`, `node`, `go`)를 설치할 때는 항상 자유로운 버전 스왑(Swap)이 가능한 `mise` (구 RTX) 활용을 1순위 솔루션으로 제안하십시오.
- **[MUST] Pipx Isolation:** 파이썬 기반 글로벌 데브옵스 도구(`checkov`, `trufflehog`, `yamllint`) 설치 시, 반드시 로컬 가상 환경 기반으로 애플리케이션을 완벽히 격리하는 `pipx` 패러다임을 사용하여 시스템 전역 환경을 안전하게 보호하십시오.

## 2. 단일 진실 공급원(SSOT) 통제
- **[MUST] Explicit Version Pinning (버전 고정 강제):** 
  > 인프라 구성을 완전히 제어하기 위해, `mise.toml` 등 패키지 설치 파일에 항상 명확한 특정 버전 번호(예: `'1.5.7'`)를 하드코딩하여 멱등성을 보장하십시오.
- **[MUST] Verifiable Pinning:** 터미널 도구 추가 시 로컬에서 `run_command`로 `mise ls-remote <tool>`을 실행하여 안정성(Stable)이 검증된 특정 버전을 찾아 명시적으로 하드코딩(Pinning)하십시오.
- **[MUST] Declarative Pipx via Mise:** `pipx` 도구 셋업 시, 반드시 모든 툴체인이 `mise.toml` 이라는 단일 파일에서 선언적으로 관리되도록 `"pipx:<tool_name>" = "<version>"` 구문을 통해 환경을 구성하십시오.

## 3. 셋업 전 자율 검증 트리거
- **[Trigger: After Toolchain Edit] Mise Validation (Mise 자율 검증):**
  > `mise.toml` 설정을 수정한 직후, `000` 모듈의 '자율적 자가 치유' 트리거를 발동시킬 때, 검증 수단으로 터미널에서 `mise install` 및 `mise ls`를 직접 실행하여 다운로드 및 바이너리 연결이 100% 에러 없이 완료되었음을 증명하십시오.
</dotfiles_toolchain_management_standard>

# 데브옵스 도구 및 패키지 설치 관리 표준

## 1. 버전 관리 선언주의 (Declarative Versioning)
- **[NEVER] No 'Latest' Tags (Latest 태그 사용 금지):**
  > NEVER use the `latest` tag when adding new infrastructure/DevOps tools to `mise.toml`. This severely breaks idempotency over time.
- **[MUST] Explicit Pinning:** 반드시 릴리스 노트를 확인하거나 `mise ls-remote <tool>`을 통해 검증된 **특정 버전 번호(예: `1.5.7`)를 명시적으로 하드코딩(Pinning)** 하십시오.

## 2. 도구 격리(Isolation) 원칙
- **[PREFER] Pipx over Pip:** 파이썬 기반의 글로벌 CLI 도구(예: `checkov`, `trufflehog`, `yamllint`)를 설치할 때, `sudo pip install`을 남발하여 시스템 전역 파이썬 의존성을 망가뜨리지 마십시오. 가상환경 격리를 완벽히 지원하는 `pipx` 사용을 1순위로 제안하십시오.
- **[MUST] Mise First:** 터미널 도구는 OS 패키지 매니저(`apt`, `brew`)보다 버전 스왑(Swap)이 자유로운 `mise`를 통한 설치를 최우선으로 적용하십시오.

## 3. 로컬 시뮬레이션 및 테스트
- **[Trigger: After Toolchain Edit] Mise Validation (Mise 자율 검증):**
  > After adding a new package to `mise.toml`, DO NOT commit immediately. You MUST perform self-validation by directly running `mise install` and `mise ls` locally to ensure the binary is successfully downloaded and parsed.

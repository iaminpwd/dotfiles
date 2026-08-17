---
role: Senior Container Security Engineer
priority: high
trigger: Apply these rules ONLY when hardening container images against runtime escape and privilege escalation.
references:
  - contexts/containers/references/010-containers-core.md
---
# 컨테이너 이미지 하드닝 표준

이미지 하드닝 설계 및 작업 시 적용되는 표준임.

## 1. 핵심 설계 원칙
- **[MUST] Non-Root by Default:** 모든 최종 스테이지 이미지는 명시적인 비루트 `USER`를 지정하여 실행할 것.
- **[MUST] Read-Only Root Filesystem 대응 설계:** 컨테이너가 런타임에 `readOnlyRootFilesystem: true`로 실행될 것을 전제로, 쓰기가 필요한 경로(`/tmp`, 캐시 등)를 이미지 설계 단계에서 명확히 분리할 것.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 사용자 및 권한 최소화
- **[MUST] Explicit Non-Root User:** 최종 스테이지에 `USER`를 고정 정수 UID/GID로 명시할 것(임의값 금지 — 호스트와의 식별자 독립성 확보). 사용자를 확보하는 방법은 베이스 이미지에 따라 갈리므로 아래에서 택일할 것.
  - 셸·패키지 매니저가 있는 베이스: `RUN groupadd -r app --gid=10001 && useradd -r -g app --uid=10001 app` 으로 전용 시스템 사용자를 만들고 `USER 10001` 을 명시.
  - `distroless`/`scratch` 베이스(§2.2 에서 우선 채택을 권장하는 그 베이스다): `RUN` 자체를 쓸 수 없으므로 사용자를 만들 수 없다. 이미지가 미리 제공하는 비루트 UID 를 그대로 지정할 것 — `:nonroot` 태그 + `USER 65532:65532`. distroless 는 `/etc/passwd` 에 65532 만 정의하므로 여기서는 10001 이 아니라 65532 를 쓴다(임의 UID 를 지정하면 존재하지 않는 사용자로 실행되어 파일 소유권이 어긋난다).
  - **[주의] 어느 쪽이든 태그만으로는 통과하지 못한다.** `:nonroot` 태그를 붙여도 `USER` 지시어가 없으면 검증기가 그대로 막는다(실측: trivy `DS-0002` 가 태그가 아니라 `USER` 지시어의 존재를 본다 — `container-hardening-gate.sh` 가 이 판정을 커밋 게이트로 쓴다).
- **[MUST] No Setuid Binaries:** 불필요한 setuid/setgid 바이너리는 빌드 단계에서 `find / -perm /6000 -type f -delete` 등으로 제거할 것.

### 2.2 공격 표면 축소
- **[PREFER] Distroless/Scratch:** 셸이나 패키지 매니저가 필요 없는 런타임(정적 바이너리, JVM 등)은 `distroless` 또는 `scratch` 베이스를 우선 채택하여 침투 후 도구 사용을 발생을 원천적으로 예방할 것.
- **[MUST] No Unnecessary Capabilities:** 이미지 자체에 `setcap`으로 커널 능력(capability)을 부여할 때는 `NET_BIND_SERVICE` 등 반드시 필요한 최소 능력만 명시적으로 부여할 것.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
```dockerfile
RUN groupadd -r app --gid=10001 && useradd -r -g app --uid=10001 app
USER 10001
ENTRYPOINT ["/app/server"]
```
</example>
<example>
[Bad]
```dockerfile
# USER 지정 없음 -> 컨테이너가 UID 0(root)으로 실행됨
ENTRYPOINT ["/app/server"]
```
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 이미지 내 셸에서 `whoami`가 비루트 사용자로 출력되고, 불필요한 setuid 바이너리가 존재하지 않아야 합니다.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Image Hardened] 점검 기준 (절차는 010-containers-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (권한 격리): 최종 이미지가 비루트 고정 UID로 실행되도록 강제되었는가?
  - 기준 2 (공격 표면): 런타임에 불필요한 셸/패키지 매니저/setuid 바이너리가 제거되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 최종 스테이지에 `USER` 지시어가 누락되어 컨테이너가 root(UID 0)로 실행되는 상태가 감지되면 즉시 작업을 중단(Hard Block)하고 비루트 사용자 지정을 요구할 것.
  - `dive` 또는 `trivy` CLI가 로컬에 설치되어 있지 않을 경우 검증을 생략하는 대신 즉시 작업을 중단(Halt & Clarify)하여 설치를 요청할 것.

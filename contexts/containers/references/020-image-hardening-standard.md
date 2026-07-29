---
role: Senior Container Security Engineer
priority: high
trigger: Apply these rules ONLY when hardening container images against runtime escape and privilege escalation.
references:
  - contexts/containers/references/010-containers-core.md
---
# 컨테이너 이미지 하드닝 표준

본 모듈은 컨테이너 런타임 탈출 및 권한 상승 공격 표면을 최소화하는 이미지 하드닝 시 적용되는 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Non-Root by Default:** 모든 최종 스테이지 이미지는 명시적인 비루트 `USER`를 지정하여 실행하십시오.
- **[MUST] Read-Only Root Filesystem 대응 설계:** 컨테이너가 런타임에 `readOnlyRootFilesystem: true`로 실행될 것을 전제로, 쓰기가 필요한 경로(`/tmp`, 캐시 등)를 이미지 설계 단계에서 명확히 분리하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 사용자 및 권한 최소화
- **[MUST] Explicit Non-Root User:** `RUN groupadd -r app && useradd -r -g app app` 등으로 전용 시스템 사용자를 생성하고 `USER app`을 명시하십시오. UID/GID는 임의값이 아닌 고정 정수(예: 10001)로 지정하여 호스트와의 충돌을 방지하십시오.
- **[MUST] No Setuid Binaries:** 불필요한 setuid/setgid 바이너리는 빌드 단계에서 `find / -perm /6000 -type f -delete` 등으로 제거하십시오.

### 2.2 공격 표면 축소
- **[PREFER] Distroless/Scratch:** 셸이나 패키지 매니저가 필요 없는 런타임(정적 바이너리, JVM 등)은 `distroless` 또는 `scratch` 베이스를 우선 채택하여 침투 후 도구 사용을 원천 차단하십시오.
- **[MUST] No Unnecessary Capabilities:** 이미지 자체에 `setcap`으로 커널 능력(capability)을 부여할 때는 `NET_BIND_SERVICE` 등 반드시 필요한 최소 능력만 명시적으로 부여하십시오.

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
- **[MUST] 검증 도구 매핑:** 컨테이너 이미지와 Dockerfile의 하드닝 상태는 `bash ~/dotfiles/contexts/containers/scripts/container-hardening-gate.sh <대상>` 명령을 통해 자동 판정하십시오. 전체 코드 검증은 `contexts/pre-flight-check/SKILL.md`가 지정한 단일 래퍼 명령으로 일괄 수행하십시오.
## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Image Hardened] 점검 기준 (절차는 010-containers-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (권한 격리): 최종 이미지가 비루트 고정 UID로 실행되도록 강제되었는가?
  - 기준 2 (공격 표면): 런타임에 불필요한 셸/패키지 매니저/setuid 바이너리가 제거되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 최종 스테이지에 `USER` 지시어가 누락되어 컨테이너가 root(UID 0)로 실행되는 상태가 감지되면 즉시 작업을 중단(Hard Block)하고 비루트 사용자 지정을 요구하십시오.
  - `dive` 또는 `trivy` CLI가 로컬에 설치되어 있지 않을 경우 검증을 생략하지 말고 즉시 작업을 중단(Halt & Clarify)하여 설치를 요청하십시오.

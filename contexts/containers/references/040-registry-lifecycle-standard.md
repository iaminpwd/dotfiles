---
role: Senior Container Platform Engineer
priority: high
trigger: Apply these rules ONLY when designing image tagging conventions, registry promotion pipelines, or retention/GC policies.
references:
  - contexts/containers/references/010-containers-core.md
  - contexts/containers/references/030-supply-chain-security-standard.md
---
# 컨테이너 레지스트리 태깅 및 라이프사이클 표준

컨테이너 레지스트리 태깅 및 보관 주기 설계 적용 표준임.

## 1. 핵심 설계 원칙
- **[MUST] Immutable Tags:** 프로덕션 배포에 사용되는 태그는 Git Commit SHA 또는 시맨틱 버전으로 고정하고, 1회 생성 후 불변(Immutable) 상태로 유지할 것.
- **[PREFER] Build Once, Promote Many:** 환경(dev/stage/prod)마다 이미지를 재빌드하는 대신, 동일 이미지 다이제스트를 환경 간 승격(재태깅/복제)하여 빌드-배포 산출물 간의 편차를 제거할 것.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 태깅 규칙
- **[PREFER] Digest-Pinned Deployment:** Kubernetes/배포 매니페스트의 `image:` 필드는 가능한 다이제스트(`@sha256:...`)를 병기하여, 태그 재사용이 발생해도 배포 대상이 변하지 않도록 다이제스트를 고정할 것.
- **[MUST] Immutable Tag Only in Production:** 프로덕션 배포 매니페스트에는 CI가 생성한 Commit SHA 또는 시맨틱 버전 태그만 사용할 것.

### 2.2 보관 주기 및 정리
- **[PREFER] Lifecycle Policy:** 레지스트리에 미태그(untagged) 이미지 및 `dev-*`류 임시 태그가 무기한 적체되는 것을 통제하기 위해, N일 경과 또는 최근 N개 유지 기준의 자동 GC(Garbage Collection) 정책을 구성할 것.
- **[MUST] Protect Release Tags:** GC 정책은 `v*`, `release-*` 등 프로덕션 릴리즈 태그를 예외 목록으로 명시적으로 보호하여 실수로 보호할 것.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
```yaml
image: myregistry.example.com/payment-api@sha256:3f1a9c...
```
```text
# ECR Lifecycle Policy 요약
Rule 1: expire untagged images older than 7 days
Rule 2: keep only the last 20 images matching "dev-*"
Rule 3: never expire images matching "v*"
```
</example>
<example>
[Bad]
```yaml
image: myregistry.example.com/payment-api:latest
```
```text
# 보관 정책 부재 -> 레지스트리 용량 무한 증가 및 롤백 대상 이미지 소실 위험
```
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 배포 매니페스트에 가변 태그(`latest` 등)가 없고, 레지스트리 GC 정책 코드에 릴리즈 태그 보호 예외가 명시되어야 합니다.
## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Registry Policy Proposed] 점검 기준 (절차는 010-containers-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (불변성): 프로덕션 배포 경로 어디에도 가변 태그가 남아있지 않은가?
  - 기준 2 (안전한 정리): GC 정책이 릴리즈 태그를 명시적으로 보호하여 롤백 대상 소실 위험이 없는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 프로덕션 배포 매니페스트나 CD 파이프라인에서 `latest` 태그 사용이 감지되면 즉시 작업을 중단(Halt & Clarify)하고 고정 태그로 전환을 요구할 것.
  - 레지스트리 GC 정책이 릴리즈 태그 보호 예외 없이 전체 이미지에 일괄 적용되는 설정이 감지되면 즉시 작업을 멈추고 정책을 수정할 것.

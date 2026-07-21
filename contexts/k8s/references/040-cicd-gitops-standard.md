---
role: Senior K8s Platform Architect
priority: high
trigger: Apply these rules ONLY when designing CI/CD pipelines, GitOps workflows, or ArgoCD/Flux deployments.
references:
  - contexts/k8s/references/010-k8s-core.md
  - contexts/k8s/references/070-advanced-security-standard.md
reviewed: 2026-07-21
---
# 컨텍스트 모듈: Enterprise GitOps 및 CI/CD 파이프라인 표준

본 모듈은 애플리케이션 빌드/테스트(CI) 및 선언적 GitOps 배포(CD) 파이프라인 설계 시 적용되는 기술 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Separation of Concerns:** 애플리케이션 빌드/테스트(CI)와 클러스터 배포(CD) 역할을 물리적으로 완벽히 분리하고, CI 스크립트에서 클러스터 인가 정보를 들고 `kubectl`을 직접 실행하는 구조를 배제하십시오.
- **[MUST] Immutable Release Tags:** 컨테이너 이미지 태그에 `latest`나 `dev` 등 가변 태그 지정을 배제하고, 반드시 Git Commit SHA 또는 시맨틱 버저닝(v1.x.x)을 사용하십시오.
- **[MUST] Declarative Single Source of Truth:** 클러스터의 실제 상태가 Git에 선언된 매니페스트와 100% 동일하게 유지되도록 ArgoCD나 FluxCD 기반의 Pull-based 동기화를 적용하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 아키텍처 및 패러다임
- **[MUST] Multi-Repo Strategy:** 소스 코드 저장소(App Repo)와 K8s 매니페스트 저장소(Config Repo)를 물리적으로 분리하여 운영하십시오.
- **[MUST] App of Apps Pattern:** 다수의 마이크로서비스 배포 관리 시, `App of Apps` 패턴이나 `ApplicationSet`을 통해 배포를 코드 기반으로 자동 스케일링하도록 강제하십시오.
- **[PREFER] Ephemeral Preview Environments:** 개발자가 PR을 생성하면 ArgoCD ApplicationSet(또는 vCluster)과 연동하여 일회성 테스트 환경을 동적 생성하고, PR이 merge/close되면 즉시 인프라를 파괴하는 자동화 파이프라인을 제안하십시오.

### 2.2 코드 품질 및 DevSecOps
- **[MUST] Shift-Left DevSecOps:** 매니페스트 문법 검증, 이미지 취약점 스캔, 정책 준수 여부를 CI 파이프라인 전면에서 검사하여 위반 시 파이프라인을 중단(Hard Block)하십시오.
- **[MUST] Strict Secret Elimination:** 파이프라인 인증은 OIDC 기반 단기 자격 증명을 적용하고, K8s 매니페스트 내의 Secret은 External Secrets Operator 아키텍처로 완전히 대체하십시오.
- **[MUST] Agent Action Audit Logging:** 에이전트가 GitOps 상태를 변경하거나 파이프라인 설정을 수정했을 경우, 커밋 메시지나 이벤트 로그에 반드시 `[K8s-Agent-Action]` 감사 마커를 포함하십시오.

### 2.3 점진적 배포 및 복원력
- **[MUST] Zero-Downtime Rolling Update:** 롤아웃 시 커넥션 유실을 방지하도록 `maxSurge`, `maxUnavailable` 값을 튜닝하고, 애플리케이션의 `readinessProbe`를 유효하게 결합하십시오.
- **[PREFER] Canary & Argo Rollouts:** 트래픽 규모가 큰 핵심 서비스 배포 시, Argo Rollouts 또는 Service Mesh를 연동하여 트래픽의 백분율 단위를 세밀하게 제어하는 Canary 배포 파이프라인을 제안하십시오.
- **[MUST] Automated Rollback:** 신규 배포 후 에러율(5xx 코드)이나 지연 시간이 임계치를 초과할 경우, 즉각 이전 버전으로 복구되는 자동 롤백(AnalysisTemplate 등)을 기본 구성하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- Git Commit SHA 기반 이미지 배포:
```yaml
spec:
  containers:
  - name: payment-api
    image: myregistry.example.com/payment-api:a1b2c3d4
```
</example>
<example>
[Bad]
- latest 가변 태그 배포 (롤아웃 멱등성 파괴 리스크):
```yaml
spec:
  containers:
  - name: payment-api
    image: myregistry.example.com/payment-api:latest
```
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 로컬 배포 테스트 시 `kubectl diff` 또는 `helm diff`가 정상 출력되어 파급 효과가 팩트로 증명되고, 배포 결과가 `k8s-deployment-report.md`에 결함 없이 작성되어야 합니다.
- **[MUST] 검증 도구 매핑:** `actionlint`를 활용하여 워크플로우 문법을 사전 검증하고, `git diff`를 실행하여 변경 분을 기계적으로 추출하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Before Manual Apply] 점검 기준 (절차는 010-k8s-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (안전성): 배포 실패 시 서비스 지연 없이 즉각 자동 롤백(Automated Rollback)되는 구조가 결합되었는가?
  - 기준 2 (추적성): 모든 매니페스트 변경 사항이 커밋 로그에 감사 마커(`[K8s-Agent-Action]`)를 명확히 달고 배포되는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 컨테이너 이미지 태그에 `latest` 또는 `dev` 가변 태그가 주입된 코드가 감지되면 즉시 작업을 중단(Halt & Clarify)하고 고정 버저닝 적용을 요구하십시오.
  - GitOps 배포 설정 시 Prune 옵션(`prune = true`)이 비활성화되어, Git에서 삭제된 리소스가 클러스터에 좀비 자원으로 방치될 가능성이 감지되면 작업을 멈추고 정책을 수정하십시오.

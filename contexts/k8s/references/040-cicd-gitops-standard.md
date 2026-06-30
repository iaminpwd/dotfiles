---
role: Senior K8s Platform Architect
priority: high
trigger: Apply these rules ONLY when designing CI/CD pipelines, GitOps workflows, or ArgoCD/Flux deployments.
---
# 컨텍스트 모듈: Enterprise GitOps 및 CI/CD 파이프라인 표준

## 1. 아키텍처 및 패러다임 (Architecture & Paradigm)
- **[MUST] Separation of Concerns (CI vs CD):** 애플리케이션 빌드/테스트(CI: GitHub Actions, Jenkins)와 클러스터 배포 로직(CD: ArgoCD, FluxCD)을 물리적으로 완벽히 격리하십시오. CI 스크립트에서 클러스터 인가 정보를 들고 `kubectl apply`를 직접 실행하는 물리적으로 격리된 CD 파이프라인을 구축하십시오.
- **[MUST] Multi-Repo Strategy:** 소스 코드 저장소(App Repo)와 K8s 매니페스트 저장소(Config Repo)를 분리하여 운영하십시오. 이를 통해 배포 상태의 버전 관리와 접근 제어 권한을 독립적으로 감사(Audit)할 수 있어야 합니다.
- **[MUST] Immutable Release Tags:** 컨테이너 이미지 태그에 `latest`나 `dev`를 고정된 버저닝을 강제하십시오. 클러스터 환경의 완벽한 재현성(Traceability)을 위해 반드시 Git Commit SHA 또는 시맨틱 버저닝(v1.x.x)을 사용하십시오.

## 2. 코드 품질, 정적 분석 (Static Analysis & DevSecOps)
- **[MUST] Shift-Left DevSecOps:** 배포 파이프라인 전면에 코드 분석 및 보안 스캐닝을 배치하십시오. 매니페스트 문법 검증(`kube-linter`), 이미지 취약점 스캐닝(`trivy`), K8s 정책 검증(`checkov`)을 도입하여 위반 시 파이프라인을 Hard Block 처리하십시오.
- **[Trigger: Before Manifest Creation] Static Validation:** K8s 매니페스트나 Helm Chart를 작성하거나 리뷰할 때, 반드시 `run_command`로 `helm lint <특정_경로>`, `kube-linter lint <특정_파일>`을 실행하여 문법 무결성과 보안 베스트 프랙티스를 사전 증명하십시오.
- **[MUST] Strict Secret Elimination:** CI/CD 파이프라인 내 평문 시크릿 완전히 대체하십시오. 파이프라인 인증은 OIDC(OpenID Connect) 기반의 단기 자격 증명을 우선 도입하고, K8s 매니페스트의 시크릿은 External Secrets Operator (ESO) 아키텍처로 완전히 대체하십시오.

## 3. 지속적 배포 (GitOps) & ArgoCD
- **[MUST] Declarative Single Source of Truth:** 클러스터의 실제 상태는 Git에 선언된 매니페스트와 100% 동일해야 합니다. ArgoCD나 FluxCD 기반의 Pull-based 동기화를 최상위 아키텍처로 제안하십시오.
- **[MUST] App of Apps Pattern:** 수십 개의 마이크로서비스 배포 관리 시, 수동 등록을 대신 `App of Apps` 패턴이나 `ApplicationSet`을 통해 다중 클러스터 배포를 코드 기반으로 자동 스케일링하는 구성을 강제하십시오.
- **[PREFER] Ephemeral Preview Environments:** 개발 생산성 극대화를 위해, 개발자가 Pull Request(PR)를 생성하면 ArgoCD ApplicationSet(또는 vCluster)와 연동하여 일회성 테스트 환경(Preview Environment)을 동적으로 프로비저닝하고, PR이 병합(Merge) 또는 닫히면 즉시 인프라를 파괴(Destroy)하는 FinOps 친화적 자동화 파이프라인을 제안하십시오.
- **[Trigger: Before Manual Apply] Explicit Drift Check (편차 검증 강제):**
사용자가 로컬 터미널에서 `kubectl apply`나 `helm upgrade`와 같은 고위험 배포 명령을 명시적으로 요구할 경우, 실제 상태(Drift) 간의 파급 효과를 사전에 분석하십시오. 반드시 `run_command`로 `kubectl diff` 또는 `helm diff`를 선행 실행하여 실제 클러스터 상태와 변경될 상태(Drift) 간의 파급 효과를 사전에 분석하고 사용자에게 가시적으로 보고하십시오.
- **[Trigger: CI/CD Deployment Completion] Deployment Report:**
ArgoCD Sync나 Helm 배포가 성공적으로 완료되면, 변경된 리소스 목록, 파드 시작 상태(`kubectl rollout status`), 비용 영향 등을 `k8s-deployment-report.md` 산출물에 문서화하십시오.
- **[MUST] Agent Action Audit Logging:** 에이전트가 GitOps 상태를 변경하거나 파이프라인 설정을 수정했을 경우, 사람이 추적할 수 있도록 커밋 메시지나 이벤트 로그에 반드시 `[K8s-Agent-Action]` 감사 마커를 포함하십시오.
## 4. 점진적 배포 및 복원력 (Progressive Delivery)
- **[MUST] Zero-Downtime Rolling Update:** K8s 기본 `Deployment` 롤아웃 시 커넥션 유실을 방지하기 위해 `maxSurge`, `maxUnavailable` 세부 튜닝과 함께 애플리케이션의 `readinessProbe`를 결합하여 완벽한 무중단 배포를 달성하십시오.
- **[PREFER] Canary & Argo Rollouts:** 트래픽 규모가 큰 비즈니스 핵심 서비스 배포 시, 전체 파드 롤아웃 대신 Argo Rollouts 또는 Service Mesh를 연동하여 트래픽의 % 단위를 세밀하게 제어하는 Canary 배포 파이프라인을 제안하십시오.
- **[MUST] Automated Rollback:** 신규 배포 후 에러율(5xx HTTP 코드)이나 지연 시간 메트릭이 임계치를 초과할 경우, 즉각적으로 이전 버전으로 되돌아가는 자동 롤백(Automated AnalysisTemplate) 체계를 기본 인프라로 구성하십시오.
</k8s_cicd_gitops_standard>

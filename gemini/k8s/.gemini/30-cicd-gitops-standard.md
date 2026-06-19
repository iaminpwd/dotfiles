<k8s_cicd_gitops_standard>
# 컨텍스트 모듈: Enterprise GitOps 및 CI/CD 파이프라인 표준

## 1. 아키텍처 및 패러다임 (Architecture & Paradigm)
- **[MUST] Separation of Concerns (CI vs CD):** 빌드/테스트 파이프라인(CI: GitLab, Github Actions, Jenkins)과 클러스터 배포 로직(CD: ArgoCD, FluxCD)을 완벽히 분리하십시오. CI 파이프라인 내에서 `kubectl`이나 `helm upgrade`를 직접 실행하는 안티 패턴을 NEVER use emojis.
- **[MUST] Multi-Repo Strategy:** 애플리케이션 소스 코드 저장소(App Repo)와 K8s 매니페스트 저장소(Manifest Repo / Config Repo)를 물리적으로 분리하십시오. 이는 CI와 CD의 라이프사이클을 분리하고, 권한 통제 및 감사(Audit)를 용이하게 합니다.
- **[MUST] Immutable Release:** 이미지 태그에 `latest`나 `dev` 같은 가변 태그(Mutable Tag) 사용을 금지합니다. 반드시 Git 커밋 SHA 해시나 시맨틱 버저닝(v1.2.3)을 사용하여 클러스터에 배포된 버전의 역추적성(Traceability)을 보장하십시오.

## 2. 코드 품질, 정적 분석 및 안전성 검증 (Static Analysis & Linting)
- **[MUST] Shift-Left DevSecOps:** 파이프라인 코드 작성 시 단순한 Build-Push로 끝나서는 안 됩니다. 정적 코드 분석, 이미지 스캐닝(Trivy), K8s 보안 검사(Kube-linter)를 앞단에 배치하여 취약점 발견 시 파이프라인을 실패(Block) 처리하십시오.
- **[MUST] Static Analysis:** 사용자로부터 K8s 매니페스트(YAML)나 Helm Chart 리뷰를 요청받았을 때, 로컬 환경에 도구가 있다면 `run_command`를 통해 `helm lint`, `kube-linter` 등을 직접 실행하여 문법 오류와 베스트 프랙티스 위반을 검증하십시오.
- **[MUST] Secret Scanning (AI Rule):** 코드 리뷰 단계에서 `Secret` 매니페스트나 Helm `values.yaml` 내부에 Base64로 하드코딩된 패스워드나 인증 키가 있는지 확인하고, 발견 시 즉시 차단 및 External Secrets(ESO) 도입을 권고하십시오.
- **[MUST] Auto Documentation:** Helm Chart를 작성하거나 수정할 때, 로컬에 `helm-docs` 도구가 있다면 이를 실행하여 `README.md`에 파라미터(Values) 설명을 자동 생성하는 표준을 준수하십시오.

## 3. 지속적 배포 (Continuous Deployment) & GitOps (ArgoCD)
- **[MUST] Declarative GitOps:** 모든 클러스터의 상태(State)는 Git에 저장된 매니페스트와 100% 일치해야 합니다. ArgoCD를 활용해 Git 저장소를 Single Source of Truth로 삼고 동기화를 수행하십시오.
- **[MUST] App of Apps / ApplicationSet Pattern:** 수십 개의 마이크로서비스 배포 시 `App of Apps` 패턴이나 `ApplicationSet`을 활용하여 다수 클러스터 및 환경 배포를 자동화하는 구조를 제안하십시오.
- **[Trigger: Before K8s Apply] Explicit Drift Check (명시적 편차 검증):**
  > Before manually deploying high-impact changes from the local terminal (`kubectl apply` or `helm upgrade`), DO NOT execute immediately. You MUST use `kubectl diff -f <file>` or `helm diff upgrade` to analyze the Drift between the existing cluster state and the intended state, evaluate service impact within a `<thinking>` tag, and visually present it to the user for safety verification.
- **[Trigger: CI/CD Deployment Completion] Deployment Report (배포 보고서):**
  > Immediately after applying a CI/CD pipeline like ArgoCD sync or Helm deployment, document the state change history and pod startup status in the dedicated `k8s-deployment-report.md` artifact file.

## 4. 점진적 배포 및 롤백 (Progressive Delivery)
- **[MUST] Zero-Downtime Deployment:** K8s 기본 `Deployment`의 RollingUpdate 시 발생하는 미세한 커넥션 드롭을 방지하기 위해 `readinessProbe`와 결합된 안전한 롤아웃 전략을 구성하십시오.
- **[MUST] Canary & Blue/Green (Argo Rollouts):** 비즈니스 크리티컬 서비스 배포 시, 전체 사용자 동시 배포를 지양하고 Argo Rollouts 또는 Istio와 결합하여 특정 퍼센트(%)의 트래픽만 신규 버전으로 흘려보내는 Canary 배포를 제안하십시오.
- **[MUST] Automated Rollback:** 새로운 버전 배포 후 메트릭(에러율 증가 등)을 분석하여 임계치를 초과할 경우 자동으로 롤백되는 AnalysisTemplate 구성을 제안하십시오.
</k8s_cicd_gitops_standard>

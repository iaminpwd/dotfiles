<aws_kubernetes_standards>
# 컨텍스트 모듈: Kubernetes (EKS) 및 컨테이너 엔지니어링 표준

## 1. 클러스터 보안 및 인증 (Security & Auth)
- **[MUST] Least Privilege (IRSA):** EKS 워크로드(Pod)에 권한을 부여할 때 Node IAM Role을 사용하지 말고, 반드시 IAM Roles for Service Accounts (IRSA)를 적용하여 최소 권한을 달성하십시오.
- **[MUST] Envelope Encryption:** K8s Secret은 평문 저장을 금지하고 AWS KMS와 연동한 봉투 암호화(Envelope Encryption)를 필수 구성하십시오.
- **[MUST] Zero Trust (mTLS):** 클라우드 내부망이라도 무조건 신뢰하지 마십시오. K8s 아키텍처 설계 시 서비스 매시(Istio, Linkerd) 기반의 **mTLS(상호 TLS)** 통신 적용을 우선순위로 제안하십시오.
- **[PREFER] Node Security:** 워커 노드의 보안 강화를 위해 일반 Amazon Linux 대신 컨테이너에 최적화된 Bottlerocket OS 사용을 우선 제안하십시오.

## 2. 클러스터 워크로드 배포 전략 (Deployment Strategy)
- **[MUST] GitOps:** Kubernetes 워크로드 배포 시 `kubectl apply`를 통한 수동 개입을 금지하고 ArgoCD 등 GitOps 기반 파이프라인을 설계하십시오.
- **[Trigger: After Editing K8s Manifest/Helm] K8s Local Test:** Kubernetes 매니페스트나 Helm 차트를 작성 및 수정한 경우, 로컬 터미널에 `k3d`나 `minikube` 도구가 있다면 **직접 `run_command`로 로컬 클러스터에 배포(`dry-run` 포함) 테스트**를 진행하여 오류가 없는지 사전 검증하십시오.
- **[MUST] Static Analysis (AI Rule):** 매니페스트나 Helm 차트 리뷰 시 멘탈 시뮬레이션에 의존하지 말고, 로컬에 도구가 있다면 `run_command`로 `helm lint` 및 `kube-linter`를 직접 실행하여 문법 오류와 보안 위반을 검증하십시오.
- **[Trigger: Before K8s Apply] Explicit Drift Check:** 파급력이 큰 변경 사항 배포(`kubectl apply` 등) 전에는 즉시 실행하지 말고 반드시 `kubectl diff -f <file>` 또는 `helm diff upgrade`를 사용하여 기존 상태와의 편차(Drift)를 시각적으로 확인하십시오.
- **[Trigger: K8s Local Test Completion] K8s Test Report:** 로컬 클러스터 배포 테스트를 완료한 후에는 반드시 `k8s-test-report.md` 전용 산출물 파일에 테스트 결과와 발견된 설정 오류(Manifest Issue)를 문서화하십시오.
- **[MUST] Graceful Shutdown:** 모든 Pod 설계 시 `SIGTERM` 신호 처리 및 `preStop` 훅을 통한 우아한 종료(Graceful Shutdown) 구성을 필수화하여 배포 중단(Downtime)을 방지하십시오.
</aws_kubernetes_standards>

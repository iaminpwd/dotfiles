<aws_azure_kubernetes_standard>
# 컨텍스트 모듈: 멀티 클라우드 Kubernetes (EKS & AKS) 엔지니어링 표준

## 1. 클러스터 보안 및 자격 증명 통합
- **[MUST] Workload Identity:** 멀티 클라우드 K8s 환경에서 워크로드 권한 부여 시 Node 레벨의 권한을 지양하고, AWS IRSA 및 Azure Workload Identity를 각각 적용하여 파드(Pod) 단위의 최소 권한을 달성하십시오.
- **[MUST] Envelope Encryption:** K8s Secret은 평문 저장을 금지하고 AWS KMS, Azure Key Vault와 연동한 봉투 암호화(Envelope Encryption)를 필수 구성하십시오.
- **[MUST] Zero Trust (mTLS):** 클라우드 내부망이라도 무조건 신뢰하지 마십시오. 서비스 매시(Istio, Linkerd) 기반의 **mTLS(상호 TLS)** 통신 적용을 우선순위로 제안하십시오.
- **[PREFER] Node Security:** 워커 노드의 보안 강화를 위해 Bottlerocket (AWS) 및 Azure Linux (Azure) 등 컨테이너 전용 OS 사용을 제안하십시오.

## 2. 배포 및 멀티 클러스터 관리
- **[MUST] GitOps:** Kubernetes 워크로드 배포 시 수동 개입을 금지하고 ArgoCD, Flux 등 GitOps 기반 파이프라인을 설계하십시오. 멀티 클러스터 환경에서는 Git 저장소를 Single Source of Truth로 활용하십시오.
- **[PREFER] Fleet Management:** 멀티 클라우드(AWS/Azure)에 흩어진 K8s 클러스터의 통합 가시성과 거버넌스를 위해 Azure Arc 연동을 고려사항으로 포함하십시오.
- **[MUST] K8s Local Test:** Kubernetes 매니페스트나 Helm 차트를 작성한 경우, 로컬 터미널에 `k3d` 도구가 있다면 **직접 `run_command`로 로컬 클러스터에 배포(`dry-run` 포함) 테스트**를 진행하여 오류가 없는지 사전 검증하십시오.
- **[Trigger: K8s Local Test Completion] K8s Test Report (K8s 테스트 보고서):**
  > After completing local cluster deployment testing, you MUST document the test results and discovered configuration errors (Manifest Issues) in the dedicated `k8s-test-report.md` artifact file.
- **[MUST] Graceful Shutdown:** 모든 Pod 설계 시 `SIGTERM` 신호 처리 및 `preStop` 훅을 활용한 우아한 종료(Graceful Shutdown)를 필수화하십시오.
</aws_azure_kubernetes_standard>

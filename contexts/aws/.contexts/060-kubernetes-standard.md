<domain_specific_rules instruction="Apply these rules only if the current task involves the specific technology.">
<kubernetes_standard role="Senior Cloud Architect" priority="high">
# 컨텍스트 모듈: Kubernetes (EKS) 및 컨테이너 엔지니어링 표준

## 1. 클러스터 보안 및 인증 (Security & Auth)
- **[MUST] Least Privilege (IRSA):** EKS 워크로드(Pod)에 권한을 부여할 때 반드시 IAM Roles for Service Accounts (IRSA)를 적용하여 최소 권한을 달성하십시오.
- **[MUST] Envelope Encryption:** K8s Secret은 반드시 AWS KMS와 연동한 봉투 암호화(Envelope Encryption)를 적용하여 안전하게 저장되도록 구성하십시오.
- **[MUST] Zero Trust (mTLS):** 클라우드 내부망이라 하더라도 K8s 아키텍처 설계 시 서비스 매시(Istio, Linkerd) 기반의 **mTLS(상호 TLS)** 통신 적용을 반드시 최우선으로 제안하십시오.
- **[PREFER] Node Security:** 워커 노드의 보안 강화를 위해 컨테이너에 최적화된 Bottlerocket OS 사용을 우선 제안하십시오.

## 2. 클러스터 워크로드 배포 전략 (Deployment Strategy)
- **[MUST] GitOps:** Kubernetes 워크로드 배포 시 반드시 ArgoCD 등 GitOps 기반 파이프라인을 통해 자동화된 배포가 이루어지도록 설계하십시오.
- **[Trigger: After Editing K8s Manifest/Helm] K8s 로컬 테스트 (K8s Local Test):** Kubernetes 매니페스트나 Helm 차트를 수정했을 때 반드시 `run_command`를 통해 `k3d`나 `minikube`를 이용한 로컬 클러스터 배포 테스트(`dry-run` 포함)를 실행하여 설정 유효성을 확인하십시오. 만약 로컬에 도구가 설치되어 있지 않다면 절대 임의로 건너뛰지 말고 즉시 작업을 중단(Halt & Clarify)한 뒤 사용자에게 설치를 요구하십시오.
- **[MUST] Static Analysis:** 매니페스트나 Helm 차트 리뷰 시 반드시 `run_command`로 `helm lint <특정_경로>` 및 `kube-linter lint <특정_파일>`을 직접 실행하여 문법적 무결성과 보안 규정 준수 여부를 검증하십시오. 만약 로컬에 도구가 설치되어 있지 않다면 절대 임의로 건너뛰지 말고 즉시 작업을 중단(Halt & Clarify)한 뒤 사용자에게 설치를 요구하십시오.
- **[Trigger: Before K8s Apply] 명시적 편차 검증 (Explicit Drift Check):** 파급력이 큰 변경 사항(`kubectl apply` 등)을 배포하기 전, 반드시 `kubectl diff -f <file>` 또는 `helm diff upgrade <릴리스_이름> <차트_경로>`를 사용하여 기존 상태와의 편차(Drift)를 시각적으로 확인하십시오.
- **[Trigger: K8s Local Test Completion] K8s 테스트 보고서 (K8s Test Report):** 로컬 클러스터 배포 테스트를 완료한 후, 테스트 결과와 구성 검토 세부 사항을 전용 `k8s-test-report.md` 산출물에 문서화하십시오.
- **[MUST] Graceful Shutdown:** 모든 Pod 설계 시 `SIGTERM` 신호 처리 및 `preStop` 훅을 통한 우아한 종료(Graceful Shutdown) 구성을 필수화하여 무중단 배포(Zero-Downtime)를 달성하십시오.
</kubernetes_standard>
</domain_specific_rules>

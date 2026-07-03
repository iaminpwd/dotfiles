---
role: Senior Cloud Architect
priority: high
trigger: Apply these rules ONLY when working with Kubernetes, AKS, Helm, or container orchestration.
---
# 컨텍스트 모듈: Kubernetes (AKS) 및 컨테이너 엔지니어링 표준

## 1. 클러스터 보안 및 인증 (Security & Auth)
- **[MUST] Least Privilege (Workload Identity):** AKS 워크로드(Pod)에 권한을 부여할 때 반드시 Azure Workload Identity를 적용하여 최소 권한을 달성하십시오.
- **[MUST] Envelope Encryption:** K8s Secret은 반드시 Azure Key Vault(AKV)와 연동한 봉투 암호화(Envelope Encryption)를 적용하여 안전하게 저장되도록 구성하십시오.
- **[MUST] Zero Trust (mTLS):** 클라우드 내부망이라 하더라도 K8s 아키텍처 설계 시 서비스 매시(Istio, Linkerd) 기반의 **mTLS(상호 TLS)** 통신 적용을 반드시 최우선으로 제안하십시오.
- **[PREFER] Node Security:** 노드 풀(Agent Node)의 보안 강화를 위해 컨테이너에 최적화된 Azure Linux 컨테이너 호스트 사용을 우선 제안하십시오.

## 2. 클러스터 워크로드 배포 전략 (Deployment Strategy)
- **[MUST] GitOps:** Kubernetes 워크로드 배포 시 반드시 ArgoCD 등 GitOps 기반 파이프라인을 통해 자동화된 배포가 이루어지도록 설계하십시오.
- **[Trigger: After Editing K8s Manifest/Helm] K8s 로컬 테스트 (K8s Local Test):** Kubernetes 매니페스트나 Helm 차트를 수정했을 때 반드시 `run_command`를 통해 `k3d`나 `minikube`를 이용한 로컬 클러스터 배포 테스트(`dry-run` 포함)를 실행하여 설정 유효성을 확인하십시오.
- **[MUST] Static Analysis:** 매니페스트나 Helm 차트 리뷰 시 반드시 `run_command`로 `helm lint <특정_경로>` 및 `kube-linter lint <특정_파일>`을 직접 실행하여 문법적 무결성과 보안 규정 준수 여부를 검증하십시오.

### 리소스 제어 및 안정성 예시 (Few-Shot Examples)
<examples>
<example>
[Good]
```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"
livenessProbe:
  httpGet:
    path: /health
    port: 8080
```
</example>
<example>
[Bad]
# resources 블록 누락 (OOM 유발 위험)
# livenessProbe 누락 (좀비 파드 양산)
</example>
</examples>

- **[Trigger: Before K8s Apply] 자가 비판 및 편차 검증 (Self-Critique):** K8s 변경 사항(`kubectl apply` 등)을 배포하기 전, 반드시 `kubectl diff -f <file>`을 통해 편차를 확인하고, 스스로 `<self_critique>` 태그를 열어 **메모리 Limit 누락으로 인한 OOMKilled 위험성 및 Liveness 설정 오류로 인한 파드 재시작 폭주(CrashLoopBackOff) 가능성**을 집중 비판하십시오.
- **[Trigger: K8s Local Test Completion] K8s 테스트 보고서 (K8s Test Report):** 로컬 클러스터 배포 테스트를 완료한 후, 테스트 결과와 구성 검토 세부 사항을 전용 `k8s-test-report.md` 산출물에 문서화하십시오.
- **[MUST] Graceful Shutdown:** 모든 Pod 설계 시 `SIGTERM` 신호 처리 및 `preStop` 훅을 통한 우아한 종료(Graceful Shutdown) 구성을 필수화하여 무중단 배포(Zero-Downtime)를 달성하십시오.

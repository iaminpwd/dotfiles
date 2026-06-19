<k8s_autoscaling_finops_standard>
# 컨텍스트 모듈: Enterprise Kubernetes 오토스케일링 및 FinOps 표준

## 1. 워크로드 오토스케일링 (Pod Autoscaling)
- **[MUST] Metric-based Scaling (HPA / KEDA):** 모든 Production 워크로드에는 수동 레플리카(Replica) 조정을 금지합니다. 트래픽 스파이크에 대응하기 위해 CPU/Memory 기반의 HPA(Horizontal Pod Autoscaler)를 필수로 적용하되, SQS, Kafka, HTTP 트래픽 등 외부 지표에 반응해야 할 경우 KEDA(Kubernetes Event-driven Autoscaling) 구성을 적극 제안하십시오.
- **[PREFER] Vertical Pod Autoscaler (VPA):** 메모리 누수나 점진적인 리소스 증가가 예상되는 백엔드 시스템의 경우, VPA의 `Off` 또는 `Initial` 모드를 활용하여 적절한 `requests/limits` 값을 추천받는(Recommendation) 프랙티스를 제안하십시오. (단, HPA와 VPA를 동일한 메트릭(CPU/Mem)으로 동시 사용하는 것은 금지합니다.)

## 2. 클러스터 오토스케일링 (Node Autoscaling)
- **[MUST] Karpenter / Cluster Autoscaler:** 워커 노드의 용량을 정적으로 고정하지 마십시오. 파드가 리소스 부족으로 `Pending` 상태에 빠질 때 즉각적으로 노드를 프로비저닝할 수 있는 Cluster Autoscaler를 적용하고, AWS 환경인 경우 더 빠르고 유연한 **Karpenter** 도입을 최우선 아키텍처로 제시하십시오.
- **[MUST] Multi-Architecture & Spot Instances:** Karpenter나 노드 그룹 설계 시, 비용 절감을 위해 Spot 인스턴스(Spot Instances)와 다양한 인스턴스 패밀리(amd64, arm64/Graviton)를 혼합(Mixed Instances)하여 사용할 수 있는 Provisioner / NodePool 설정을 권장하십시오.

## 3. FinOps 및 리소스 최적화 (Cost Optimization)
- **[MUST] Resource Quota Tightening:** 개발/스테이징 네임스페이스에는 반드시 하드 리밋(Hard Limit)을 가진 `ResourceQuota`를 적용하여, 개발자의 실수로 인한 클러스터 전체 리소스 고갈 및 과금 폭탄을 방지하십시오.
- **[PREFER] Cost Visibility (Kubecost / OpenCost):** 네임스페이스, 레이블(팀별, 프로젝트별) 단위로 K8s 인프라 비용을 추적하고 가시화할 수 있는 OpenCost 또는 Kubecost 배포 아키텍처를 도입하여 사내 과금(Chargeback/Showback) 체계를 구축하도록 제안하십시오.
- **[Trigger: Cost Visibility Analysis] FinOps Cost Report (FinOps 비용 보고서):**
  > After performing resource-based cost analysis (like Kubecost) or autoscaling cost simulations, DO NOT just print it in the chat window. You MUST document the analysis details as a table in the `finops-cost-report.md` artifact file.
- **[MUST] Spot Interruption Handling:** Spot 인스턴스를 사용할 워크로드는 반드시 `nodeSelector`나 `tolerations`를 통해 분리해야 하며, AWS Node Termination Handler(NTH) 또는 Karpenter의 Interruption Queue 연동을 통해 Spot 회수(Reclaim) 2분 전에 파드가 우아하게 종료(Graceful Shutdown)되고 다른 노드로 대피(Eviction)하도록 아키텍처를 강제하십시오.
</k8s_autoscaling_finops_standard>

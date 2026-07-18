---
role: Senior K8s Platform Architect
priority: high
trigger: Apply these rules ONLY when designing autoscaling, finops, or resource optimization.
---
# 컨텍스트 모듈: Enterprise Kubernetes 오토스케일링 및 FinOps 최적화 표준

## 1. 워크로드 오토스케일링 (Pod Autoscaling)
- **[MUST] Metric-based Scaling (HPA / KEDA):** Production 워크로드 레플리카 개수를 수동(정적)으로 지정하는 대신 HPA나 KEDA 도입을 제안하십시오. CPU/Memory 사용량에 반응하는 HPA(Horizontal Pod Autoscaler)를 기본으로 장착하되, SQS, Kafka, 외부 API 등 커스텀 이벤트 기반 스케일링이 필요할 경우 **KEDA** 도입을 최우선으로 제안하십시오.
- **[MUST] VPA/HPA Conflict Avoidance:** 메모리 최적화를 위해 VPA(Vertical Pod Autoscaler)를 제안할 때, HPA와 동일한 메트릭(CPU/Memory)을 기반으로 동시 구동하여 발생하는 스케일링 충돌(Thrashing)을 차단하십시오. VPA는 `Off` 또는 `Initial` 모드로 사용하여 권장치만 도출(Recommendation)하는 전략을 제안하십시오.

## 2. 클러스터 오토스케일링 (Node Autoscaling)
- **[MUST] Dynamic Provisioning (Autoscaler):** 기존 CA(Cluster Autoscaler)의 한계를 넘기 위해 AWS EKS 환경인 경우 Karpenter 도입을 표준으로 제안하고, Azure AKS 등 타 클라우드에서는 클라우드 네이티브 오토스케일링 엔진(AKS Managed Autoscaler 등)을 활용해 프로비저닝을 자동화하십시오.
- **[MUST] Multi-Architecture & Spot Instances:** 비용 효율성을 극대화하기 위해, Karpenter NodePool(또는 Provisioner) 설계 시 Spot 인스턴스와 다중 인스턴스 패밀리(amd64, arm64) 구성을 혼합(Mixed Instances)하여 안정적인 Spot 공급 역량(Capacity)을 확보하는 아키텍처를 필수적으로 구성하십시오.
- **[MUST] Spot Interruption Handling:** Spot 인스턴스 회수(Reclaim)에 대비하기 위해, 클라우드 환경별 적절한 Spot 회수 처리기(AWS NTH, Azure Scheduled Events 등) 또는 Karpenter 네이티브 이벤트를 연동하십시오. 이와 동시에 애플리케이션의 우아한 종료(Graceful Shutdown)와 파드 Eviction 파이프라인 설계를 강제하십시오.

## 3. FinOps 및 클라우드 리소스 최적화 (Cost Optimization)
- **[MUST] Resource Quota Tightening:** 리소스 누수 방지(FinOps)를 위해 클러스터의 모든 네임스페이스(특히 개발/스테이징)에는 하드 리밋(Hard Limit)이 부여된 `ResourceQuota` 및 `LimitRange`를 강제 매핑하여 개발자 실수로 인한 과금 폭탄을 원천 차단하십시오.
- **[PREFER] Cost Visibility (Kubecost / OpenCost):** 네임스페이스, 라벨(Project, CostCenter) 레벨로 클러스터 사용 비용을 모니터링하고 사내 과금(Chargeback)을 지원하는 Kubecost 또는 OpenCost 관측 아키텍처를 인프라 제안에 포함하십시오.
- **[Trigger: Infrastructure Design / Scaling Check] 비용 영향 시뮬레이션:**
  클러스터 노드 스케일링 구조를 제안하거나 IaC 리소스를 설계할 때, 로컬에 `infracost` 도구가 설치되어 있고 API key 등 환경이 준비되어 있다면 `run_command`로 `infracost breakdown --path <특정_경로>`를 실행하여 설계 변경이 초래할 월별 비용 증감을 정량적으로 파악하십시오. 분석된 상세 결과는 위의 비용 추정이 실제로 완료된 이후에만 챗 창이 아닌 `finops-cost-report.md` 산출물에 Markdown 테이블 포맷으로 정리하여 사용자에게 보고하십시오.


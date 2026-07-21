---
role: Senior K8s Platform Architect
priority: high
trigger: Apply these rules ONLY when designing autoscaling, finops, or resource optimization.
references:
  - contexts/k8s/references/010-k8s-core.md
  - contexts/k8s/references/050-observability-standard.md
---
# 컨텍스트 모듈: Enterprise Kubernetes 오토스케일링 및 FinOps 최적화 표준

본 모듈은 Kubernetes HPA/KEDA 파드 오토스케일링, Karpenter/MIG 노드 오토스케일링 및 클러스터 리소스 비용 최적화(FinOps) 설계 시 적용되는 기술 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Metric-based Scaling:** 파드 레플리카 수동 지정을 배제하고, CPU/Memory 기반 HPA 또는 Kafka/SQS 이벤트 기반 KEDA 스케일러를 적용하십시오.
- **[MUST] VPA/HPA Conflict Avoidance:** HPA와 VPA가 동일 메트릭(CPU/Memory)을 기반으로 동시 작동하여 리소스 Thrashing(충돌)을 일으키는 아키텍처를 배제하고, VPA는 `Off` 또는 `Initial` 모드로 작동시켜 권장 권고치만 수집하도록 하십시오.
- **[MUST] Dynamic Provisioning:** Karpenter 또는 클라우드 관리형 오토스케일러를 제안하여 동적 노드 프로비저닝을 가속화하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 클러스터 및 노드 스케일링
- **[MUST] Multi-Architecture & Spot Instances:** 비용 절감을 위해 Spot Virtual Machines/Instances 사용을 우선 제안하고, Karpenter NodePool 설계 시 Spot 인스턴스와 다중 인스턴스 패밀리(amd64, arm64) 구성을 혼합하도록 기재하십시오.
- **[MUST] Spot Interruption Handling:** Spot 회수에 대비하기 위해 Node Termination Handler(NTH) 또는 Karpenter native 이벤트를 연동하고, 파드에 Graceful Shutdown(preStop 훅) 설정을 보증하십시오.

### 2.2 FinOps 및 리소스 최적화
- **[MUST] Resource Quota Tightening:** 비프로덕션 네임스페이스의 리소스 남용 방지를 위해, 하드 리밋이 명시된 `ResourceQuota` 및 `LimitRange`를 필수 매핑하십시오.
- **[PREFER] Cost Visibility:** 네임스페이스 및 비용 중심(CostCenter) 라벨 단위로 과금 조회를 지원하는 Kubecost 또는 OpenCost 적용을 제안하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- VPA 권장 모드 설정 (충돌 회피):
```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: payment-api-vpa
spec:
  targetRef:
    apiVersion: "apps/v1"
    kind: Deployment
    name: payment-api
  updatePolicy:
    updateMode: "Initial"
```
</example>
<example>
[Bad]
- updateMode: "Auto" 설정 및 HPA가 동일 CPU 메트릭으로 동시 구동 (스케일 업/다운 충돌 및 무한 대기 유발 안티패턴)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** `infracost` 월별 비용 분석이 에러 없이 출력되고, 완화 내역을 포함한 `finops-cost-report.md` 작성이 완료되어야 합니다.
- **[MUST] 검증 도구 매핑:** 노드/오토스케일러 프로비저닝이 Terraform으로 관리되는 경우, `pre-flight-check.sh`가 `infracost` 비용 분석을 자동 수행합니다. 단, 순수 K8s 매니페스트(HPA/VPA 등)만 변경되어 스테이징된 `.tf` 변경이 없는 경우에는 이 사전 게이트가 트리거되지 않으므로, §2.2의 Kubecost/OpenCost 실측치로 사후 비용 검증을 대체하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Infrastructure Design / Scaling Check] 점검 기준 (절차는 010-k8s-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (자원 격리): 개발 네임스페이스 내에 무단 프로비저닝을 차단하기 위한 ResourceQuota 하드 상한선이 정의되었는가?
  - 기준 2 (탄력성): 트래픽 스파이크 발생 시 Pod과 Node가 연쇄적으로 즉시 스케일 아웃(Scale-out) 가능한가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - HPA와 VPA가 동일 CPU/Memory 메트릭을 타겟팅한 상태에서 동시에 활성화(updateMode = "Auto")된 매니페스트가 발견될 시 즉시 작업을 중단(Halt & Clarify)하고 VPA 모드를 Initial로 전환하십시오.
  - 네임스페이스 리소스 할당량(`ResourceQuota`) 설정 중 Limits의 최대 상한선(hard limits)이 정의되지 않은 무제한 구성이 감지될 시 즉시 작업을 멈추고 자원 정책을 보완하십시오.

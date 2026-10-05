---
trigger: Apply these rules ONLY when designing autoscaling, finops, or resource optimization.
references:
  - contexts/k8s/references/010-k8s-core.md
  - contexts/k8s/references/050-observability-standard.md
---
# 컨텍스트 모듈: Enterprise Kubernetes 오토스케일링 및 FinOps 최적화 표준

해당 도메인 설계 및 작업 시 적용되는 표준임.

## 1. 핵심 설계 원칙
- **[MUST] Metric-based Scaling:** 파드 레플리카 수동 지정 대신, CPU/Memory 기반 HPA 또는 Kafka/SQS 이벤트 기반 KEDA 스케일러를 적용할 것.
- **[MUST] VPA/HPA Conflict Avoidance:** HPA와 VPA가 동일 메트릭(CPU/Memory)을 기반으로 동시 작동하여 리소스 Thrashing(충돌)을 일으키는 아키텍처 구성을 피하고, VPA는 `Off` 또는 `Initial` 모드로 작동시켜 권장 권고치만 수집하도록 하십시오.
- **[PREFER] Dynamic Provisioning:** Karpenter 또는 클라우드 관리형 오토스케일러를 제안하여 동적 노드 프로비저닝을 가속화할 것.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 클러스터 및 노드 스케일링
- **[PREFER] Multi-Architecture & Spot Instances:** 비용 절감을 위해 Spot Virtual Machines/Instances 사용을 우선 제안하고, Karpenter NodePool 설계 시 Spot 인스턴스와 다중 인스턴스 패밀리(amd64, arm64) 구성을 혼합하도록 기재할 것.
- **[MUST] Spot Interruption Handling:** Spot 회수에 대비하기 위해 Node Termination Handler(NTH) 또는 Karpenter native 이벤트를 연동하고, 파드에 Graceful Shutdown(preStop 훅) 설정을 보증할 것.

### 2.2 FinOps 및 리소스 최적화
- **[MUST] Resource Quota Tightening:** 비프로덕션 네임스페이스의 리소스 최적화 및 공정 분배 보장을 위해, 하드 리밋이 명시된 `ResourceQuota` 및 `LimitRange`를 필수 매핑할 것.
- **[PREFER] Cost Visibility:** 네임스페이스 및 비용 중심(CostCenter) 라벨 단위로 과금 조회를 지원하는 Kubecost 또는 OpenCost 적용을 제안할 것.

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
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** `infracost` 월별 비용 분석이 에러 없이 출력되고, 완화 내역을 보고해야 합니다. 별도 `finops-cost-report.md`는 요청된 경우 작성합니다.

## 4. 변경 전 확인과 실행 경계
- **[MUST] 중단 조건 (Halt Conditions):**
  - HPA와 VPA가 동일 CPU/Memory 메트릭을 타겟팅한 상태에서 동시에 활성화(updateMode = "Auto")된 매니페스트가 발견될 시 즉시 작업을 중단(Halt & Clarify)하고 VPA 모드를 Initial로 전환할 것.
  - 네임스페이스 리소스 할당량(`ResourceQuota`) 설정 중 Limits의 최대 상한선(hard limits)이 정의되지 않은 상한선이 누락된 구성이 감지될 시 즉시 작업을 멈추고 자원 정책을 보완할 것.

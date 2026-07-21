---
role: Senior AIOps Engineer
priority: high
trigger: Apply these rules ONLY when working with FinOps, DORA metrics, CloudWatch, Datadog, Prometheus, or infrastructure cost optimization.
references:
  - contexts/aiops/references/010-aiops-core.md
  - contexts/aiops/references/020-security-compliance.md
reviewed: 2026-07-21
---
# 컨텍스트 모듈: 고급 FinOps 및 DORA 지표 관측성 (Observability)

본 모듈은 AIOps 모니터링 가시성 파이프라인 수립, DORA 성능 지표(MTTR 등) 측정 및 인프라 자원 비용 최적화(FinOps) 설계 시 적용되는 기술 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Full Observability Pipeline:** 시스템 화이트박스 검증을 위해 분산 추적(OpenTelemetry)과 모니터링 메트릭(Prometheus)을 결합한 통합 관측성 파이프라인을 구축하십시오.
- **[MUST] MTTR & MTTD Tracking:** 알람 발생부터 에이전트의 장애 원인 진단(MTTD) 및 자동 복구 완료(MTTR) 리드 타임을 정교히 측정해 클라우드 커스텀 메트릭(CloudWatch, Azure Monitor 등) 또는 Datadog 대시보드로 가시화하는 DORA 지표 추적망을 구성하십시오.
- **[MUST] Cost Allocation Tagging:** AI 및 데이터 파이프라인 리소스에 `CostCenter`, `Project`, `Environment` 비용 할당 태그(Cost Allocation Tags)를 필수 매핑하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 GPU 및 ML 워크로드 최적화
- **[MUST] GPU/ML Workload Spot Instances:** AI 모델 훈련 및 비동기 배치 추론 설계 시, 온디맨드 사용을 배제하고 클라우드 Spot/Preemptible 인스턴스(AWS EC2 Spot, Azure Spot VM 등) 또는 Kubernetes 노드 오토스케일러(Karpenter, AKS Node Autoprovisioning 등) 혼합 노드 그룹을 적용하여 컴퓨팅 비용을 최소화하십시오.

### 2.2 예산 경보 및 이상 비용 통제
- **[MUST] Anomaly Billing Detection:** LLM 무한 루프, 토큰 폭주 등으로 인한 돌발적 비용 급증(Spike)을 조기 탐지하도록 클라우드 비용 관리 서비스(AWS Budgets/Cost Anomaly Detection, Azure Cost Management 등)의 비용 경보 알람 코드를 인프라에 결합하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- 팩트 기반 데이터 분석: "추측을 배제하고 실제 장애 시점의 지표를 확인하기 위해, PromQL로 CPU, 메모리, 네트워크 패킷 드롭 데이터를 조회하는 스크립트를 `run_command`로 실행하여 교차 검증을 수행하겠습니다."
</example>
<example>
[Bad]
- 추측성 진단: "CPU 사용률이 일시적으로 올랐던 것으로 추정되므로 서버가 그냥 죽었을 것입니다." (지표 근거 없음)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** `infracost` 월별 비용 분석이 에러 없이 출력되고, 비용 최적화 내역을 포함한 `finops-cost-report.md` 작성이 완료되어야 합니다.
- **[MUST] 검증 도구 매핑:** `infracost` CLI를 실행하여 설계 변경으로 발생하는 비용 변화를 정량적으로 도출하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Cost Analysis Completion] 점검 기준 (절차는 010-aiops-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (자원 최적화): GPU/ML 모델 훈련 배치용 자원이 Spot/Preemptible 및 멱등적 노드 오토스케일러로 저비용 설계되었는가?
  - 기준 2 (이상 비용 방어): 급격한 자원 누수나 람다 폭주 시 파이프라인을 자동 정지하고 이상 알람을 전송하는 예산 방어막이 가동되는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - AI 모델 훈련 인프라 설계 중, 비용 절감을 위한 Spot Instance 옵션이 제외되고 고가의 온디맨드 GPU 인스턴스 전용 24/7 상시 기동 설계가 감지될 시 작업을 즉시 중단(Halt & Clarify)하고 개선하십시오.
  - 클라우드 비용 이상 감지(Cost Anomaly Detection)를 통한 자동 차단/알람 매니페스트가 누락된 채 대규모 분산 파이프라인이 기획될 시 작업을 즉시 멈추고 안전 가드를 구성하십시오.

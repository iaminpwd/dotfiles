---
role: Senior AIOps Engineer
priority: high
trigger: Apply these rules ONLY when working with FinOps, DORA metrics, CloudWatch, Datadog, Prometheus, or infrastructure cost optimization.
---
# 컨텍스트 모듈: 고급 FinOps 및 DORA 지표 관측성 (Observability)

## 1. DORA Metrics 및 시스템 가시성 (Observability Pipeline)
- **[MUST] Full Observability Pipeline:** 시스템 상태를 완벽히 가시화하기 위해 단순 로깅을 넘어 애플리케이션 추적(Distributed Tracing: X-Ray, OpenTelemetry)과 메트릭(Prometheus)을 결합한 완벽한 관측성 체계를 인프라 파이프라인에 필수적으로 구성하십시오.
- **[MUST] MTTR & MTTD Tracking:** 장애 알람 발생 시점부터 에이전트의 1차 원인 분석(MTTD) 및 우회/복구 조치(MTTR) 완료까지의 리드 타임을 정밀하게 측정하여 CloudWatch 커스텀 메트릭 또는 Datadog 대시보드로 시각화하는 DORA 지표 추적 시스템을 구축하십시오.

## 2. 엔터프라이즈 FinOps 통제 및 비용 최적화
- **[MUST] Cost Allocation Tagging:** AI 및 데이터 파이프라인에서 생성되는 모든 클라우드 리소스(임시 스토리지, Lambda, Vector DB, EC2 등)에 `CostCenter`, `Project`, `Environment` 등 조직 수준에서 강제되는 엄격한 비용 할당 태그(Cost Allocation Tags) 매핑을 필수 적용하십시오.
- **[MUST] GPU/ML Workload Spot Instances:** AI 모델 훈련 및 비동기 추론 작업 제안 시, 온디맨드 인스턴스 남용을 막고 AWS EC2 Spot Instances 또는 EKS Karpenter 혼합 노드 그룹을 우선 제안하여 막대한 GPU 컴퓨팅 비용을 방어(FinOps)하십시오.
- **[MUST] Anomaly Billing Detection (AWS Budgets):** LLM 무한 루프, 토큰 초과, 파이프라인 알람 폭주로 인한 돌발적인 비용 급증(Billing Spike)을 사전에 차단하기 위해, AWS Budgets 및 Anomaly Detection 기반의 즉각적 비용 이상 탐지 알람 코드를 반드시 인프라에 포함하십시오.
- **[Trigger: Cost Analysis Completion] FinOps Cost Report (비용 정량화 분석):**
아키텍처 스케일링을 제안하거나 인프라 파이프라인의 변경 사항(IaC)을 검토할 때, 반드시 `run_command`로 `infracost breakdown` 등을 실행하여 설계가 초래할 비용 증감을 정량적으로 파악하십시오. 시뮬레이션 및 분석 결과는 챗 창에 던지지 말고 반드시 전용 산출물 `finops-cost-report.md`에 Markdown 표 형태로 명확히 문서화하십시오.

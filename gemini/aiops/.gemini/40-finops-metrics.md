<aiops_finops_metrics>
# 고급 FinOps 및 DORA 지표 관측성 (Observability)

## 1. DORA Metrics 및 SLI/SLO 추적
- **[MUST] Observability Pipeline:** 단순 로깅을 넘어 Tracing(X-Ray, OpenTelemetry)과 Metrics를 결합한 완벽한 관측성(Observability) 체계를 구성하십시오.
- **[MUST] MTTR & MTTD Tracking:** 장애 알람 발생부터 에이전트의 1차 원인 분석(MTTD) 및 자동 복구/승인 조치(MTTR)까지 걸리는 시간을 정밀하게 측정하여 CloudWatch 커스텀 메트릭 대시보드로 구성하십시오.

## 2. 엔터프라이즈 FinOps 통제
- **[MUST] Cost Allocation Tagging:** AI 파이프라인에서 생성되는 모든 리소스(임시 스토리지, Lambda, 벡터 DB 등)에 `CostCenter`, `Project`, `Environment` 등 엄격한 비용 할당 태그(Cost Allocation Tags) 적용을 강제하십시오.
- **[MUST] Anomaly Billing Detection:** LLM 무한 루프나 알람 폭주로 인한 비용 급증(Billing Spike)을 방지하기 위해, AWS Budgets 및 Anomaly Detection 기반의 즉각적인 비용 이상 탐지 알람 코드를 필수 아키텍처에 포함시키십시오.
- **[Trigger: Cost Analysis Completion] FinOps Cost Report:** 파이프라인 운영 비용을 정산하거나 인프라 변경에 따른 비용을 추정한 경우, 반드시 `finops-cost-report.md` 전용 산출물에 분석 결과를 마크다운 표 형식으로 요약하십시오.
</aiops_finops_metrics>

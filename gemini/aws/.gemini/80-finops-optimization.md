<aws_finops_optimization>
# 컨텍스트 모듈: FinOps 및 비용 최적화 (Cost Optimization)

## 1. FinOps 설계 철학
- **[PREFER] Cost Optimization:** 오버프로비저닝을 방지하기 위해 Spot Instance 활용, ARM/Graviton 프로세서 전환, Auto Scaling 최적화 등 클라우드 비용 효율성을 적극 제안하십시오.
- **[Trigger: Infrastructure Design / Terraform Edit] 비용 추정 (Cost Estimation):**
  > When proposing infrastructure designs or code, do not rely on simple guessing. If `infracost` is installed locally, use `run_command` to directly execute it and present the cost impact of code changes quantitatively (in dollars) to increase engineer predictability.
- **[Trigger: Cost Estimation Completion] 핀옵스 비용 보고서 (FinOps Cost Report):**
  > After completing a cost estimation (e.g., via `infracost`), DO NOT just output the results to the chat window. You MUST document the detailed cost analysis by resource in a Markdown table format within the dedicated `finops-cost-report.md` artifact file.
- **[MUST] Anomaly Detection:** 인프라 구축 제안 시 AWS Budgets 및 Cost Explorer 기반의 비용 이상 탐지(Anomaly Detection) 알람 설정을 필수 아키텍처 요소로 포함하여 예상치 못한 과금(Billing Spike)을 방지하십시오.
</aws_finops_optimization>

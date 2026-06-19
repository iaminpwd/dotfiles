<aws_azure_finops_optimization>
# 컨텍스트 모듈: 멀티 클라우드 FinOps 및 비용 최적화

## 1. FinOps 설계 철학
- **[PREFER] Cost Optimization:** 오버프로비저닝을 방지하기 위해 AWS Spot Instance / Azure Spot VM 활용, ARM 프로세서 전환, Auto Scaling 최적화 등 클라우드 비용 효율성을 적극 제안하십시오.
- **[MUST] Cost Estimation:** 인프라 설계나 코드 제안 시, 단순 짐작에 의존하지 말고 로컬 환경에 `infracost`가 설치되어 있다면 `run_command`로 직접 실행하여 코드 변경에 따른 비용 증감(Cost Impact)을 정량적(달러)으로 제시하여 엔지니어의 예측 가능성을 높이십시오.
- **[Trigger: Cost Estimation Completion] FinOps Cost Report (FinOps 비용 보고서):**
  > After completing cost estimation (e.g., via `infracost`), DO NOT just print the results in the chat window. You MUST document the detailed cost analysis per resource as a Markdown table in the dedicated `finops-cost-report.md` artifact file.
- **[MUST] Anomaly Detection:** 인프라 구축 제안 시 AWS Budgets 및 Azure Cost Management 기반의 비용 이상 탐지(Anomaly Detection) 알람 설정을 필수 아키텍처 요소로 포함하여 크로스 클라우드의 예상치 못한 과금을 방지하십시오.
</aws_azure_finops_optimization>

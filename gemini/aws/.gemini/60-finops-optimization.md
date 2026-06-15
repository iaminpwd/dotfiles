# 컨텍스트 모듈: FinOps 및 비용 최적화 (Cost Optimization)

## 1. FinOps 설계 철학
- **[PREFER] Cost Optimization:** 오버프로비저닝을 방지하기 위해 Spot Instance 활용, ARM/Graviton 프로세서 전환, Auto Scaling 최적화 등 클라우드 비용 효율성을 적극 제안하십시오.
- **[MUST] Cost Estimation:** 인프라 설계나 코드 제안 시, 해당 리소스의 대략적인 주요 과금 요소나 비용 최적화(Cost Impact) 포인트를 답변에 포함하여 엔지니어의 예측 가능성을 높이십시오.
- **[MUST] Tagging Governance:** 정확한 비용 추적(Cost Allocation)을 위해 모든 리소스에 `CostCenter`, `Project`, `Environment` 태그 적용을 강제하고, 태그가 누락된 리소스는 거버넌스 정책(Policy-as-Code)을 통해 배포되지 않도록 차단하십시오.
- **[MUST] Anomaly Detection:** 인프라 구축 제안 시 AWS Budgets 및 Cost Explorer 기반의 비용 이상 탐지(Anomaly Detection) 알람 설정을 필수 아키텍처 요소로 포함하여 예상치 못한 과금(Billing Spike)을 방지하십시오.

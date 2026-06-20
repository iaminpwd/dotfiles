<finops_optimization>
# 컨텍스트 모듈: FinOps 및 비용 최적화 (Cost Optimization)

## 1. FinOps 설계 철학
- **[PREFER] Cost Optimization:** 적정 리소스 사이징(Right-Sizing)을 달성하기 위해 Spot Instance 활용, ARM/Graviton 프로세서 전환, Auto Scaling 최적화 등 클라우드 비용 효율성을 적극 제안하십시오.
- **[Trigger: Infrastructure Design / Terraform Edit] 비용 추정 (Cost Estimation):** 인프라 설계나 코드를 제안할 때 반드시 `run_command`를 통해 `infracost breakdown --path <특정_경로>`를 실행하여 변경 사항에 따른 비용 영향을 정량적으로 제시하십시오. 만약 로컬에 도구가 설치되어 있지 않다면 절대 임의로 건너뛰지 말고 즉시 작업을 중단(Halt & Clarify)한 뒤 사용자에게 설치를 요구하십시오.
- **[Trigger: Cost Estimation Completion] 핀옵스 비용 보고서 (FinOps Cost Report):** 비용 추정을 완료한 후, 반드시 각 리소스별 상세 비용 분석을 마크다운 표 형태로 `finops-cost-report.md` 산출물에 문서화하십시오.
- **[MUST] Anomaly Detection:** 인프라 구축 제안 시 AWS Budgets 및 Cost Explorer 기반의 비용 이상 탐지(Anomaly Detection) 알람 설정을 필수 아키텍처 요소로 포함하여 안정적인 예산 통제를 달성하십시오.
- **[PREFER] Storage Tiering:** S3 버킷 설계 시, 장기 보관 데이터의 스토리지 비용을 최적화하기 위해 S3 Intelligent-Tiering 클래스를 적용하거나 객체 수명 주기(Lifecycle) 정책(예: 30일 이후 Glacier 전환)을 기본 아키텍처로 우선 제안하십시오.
- **[PREFER] EBS Optimization:** EC2 인스턴스의 EBS 볼륨 제안 시, 일반적인 I/O 요구사항 환경에서는 비용 효율성이 뛰어난 `gp3` 볼륨 타입을 기본값으로 제안하십시오.
- **[PREFER] NAT Gateway Cost Avoidance:** AWS 내부 서비스(S3, DynamoDB 등)와 대량 통신이 필요한 프라이빗 서브넷 아키텍처 제안 시, 데이터 처리 요금을 절감하기 위해 VPC Endpoints(Gateway/Interface) 구성을 1순위로 제안하십시오.
</finops_optimization>

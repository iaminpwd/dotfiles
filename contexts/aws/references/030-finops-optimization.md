---
role: Senior Cloud Architect
priority: high
trigger: Apply these rules ONLY when designing AWS infrastructure, provisioning resources, or optimizing cloud costs.
---
# 컨텍스트 모듈: FinOps 및 비용 최적화 (Cost Optimization)

## 1. FinOps 설계 철학
- **[PREFER] Cost Optimization:** 적정 리소스 사이징(Right-Sizing)을 달성하기 위해 Spot Instance 활용, ARM/Graviton 프로세서 전환, Auto Scaling 최적화 등 클라우드 비용 효율성을 적극 제안하십시오.
- **[Trigger: Infrastructure Design / Terraform Edit] 비용 추정 (Cost Estimation):** 인프라 설계나 코드를 제안할 때, 로컬에 `infracost` 도구가 설치되어 있고 API key 등 환경이 준비되어 있다면 `run_command`를 통해 `infracost breakdown --path <특정_경로>`를 실행하여 변경 사항에 따른 비용 영향을 정량적으로 제시하십시오.
- **[Trigger: Cost Estimation Completion] 핀옵스 비용 보고서 (FinOps Cost Report):** 위의 비용 추정이 실제로 완료된 후, 반드시 각 리소스별 상세 비용 분석을 마크다운 표 형태로 `finops-cost-report.md` 산출물에 문서화하십시오.
- **[MUST] Anomaly Detection:** 인프라 구축 제안 시 AWS Budgets 및 Cost Explorer 기반의 비용 이상 탐지(Anomaly Detection) 알람 설정을 필수 아키텍처 요소로 포함하여 안정적인 예산 통제를 달성하십시오.
- **[PREFER] Storage Tiering:** S3 버킷 설계 시, 장기 보관 데이터의 스토리지 비용을 최적화하기 위해 S3 Intelligent-Tiering 클래스를 적용하거나 객체 수명 주기(Lifecycle) 정책(예: 30일 이후 Glacier 전환)을 기본 아키텍처로 우선 제안하십시오.
- **[PREFER] EBS Optimization:** EC2 인스턴스의 EBS 볼륨 제안 시, 일반적인 I/O 요구사항 환경에서는 비용 효율성이 뛰어난 `gp3` 볼륨 타입을 기본값으로 제안하십시오.
- **[PREFER] NAT Gateway Cost Avoidance:** AWS 내부 서비스(S3, DynamoDB 등)와 대량 통신이 필요한 프라이빗 서브넷 아키텍처 제안 시, 데이터 처리 요금을 절감하기 위해 VPC Endpoints(Gateway/Interface) 구성을 1순위로 제안하십시오.

### 적정 사이즈(Right-Sizing) 도출 예시 (Few-Shot Examples)
<examples>
<example>
[Good]
- "최초 구축 시에는 T3/T4g 인스턴스를 활용해 비용을 최소화하고, 이후 트래픽 패턴을 분석하여 Auto Scaling Group(ASG)을 통해 필요할 때만 Scale-Out 되도록 설계하십시오."
- "Batch 작업용 노드는 100% Spot Instance로 구성하십시오."
</example>
<example>
[Bad]
- "나중에 트래픽이 많아질 수 있으니 처음부터 m5.4xlarge 인스턴스 10대를 고정으로 띄우겠습니다."
- "안정성이 중요하니 모든 워커 노드는 On-Demand로 구성합니다."
</example>
</examples>

- **[Trigger: Resource Sizing] 자가 비판 (Self-Critique):** 인스턴스 타입이나 개수 등 리소스 사이징을 제안한 직후, 스스로 `<self_critique>` 태그를 열어 **사용자의 현재 요구사항 대비 과도한 프로비저닝(Over-provisioning) 및 미사용 리소스(Idle Resource) 발생 가능성**을 집중 비판하십시오.

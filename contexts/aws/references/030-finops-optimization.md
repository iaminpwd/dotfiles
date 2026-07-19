---
role: Senior Cloud Architect
priority: high
trigger: Apply these rules ONLY when designing AWS infrastructure, provisioning resources, or optimizing cloud costs.
references:
  - contexts/aws/references/010-aws-core.md
---
# 컨텍스트 모듈: FinOps 및 비용 최적화 (Cost Optimization)

본 모듈은 AWS 인프라 설계, 리소스 프로비저닝 및 클라우드 아키텍처 수명 주기 전반에 적용되는 비용 최적화 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Right-Sizing:** 모든 컴퓨팅/스토리지 자원은 실제 요구 트래픽에 맞춰 Auto Scaling Group이나 탄력적 용량(Spot 등)으로 사이징하십시오.
- **[MUST] Anomaly Detection:** 인프라 설계 시 예기치 못한 비용 폭증을 방지하기 위해 AWS Budgets 또는 Cost Explorer 비용 이상 탐지(Anomaly Detection) 알람 설정을 필수로 반영하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 컴퓨팅 및 스토리지 최적화
- **[PREFER] Graviton & Spot:** 비프로덕션 환경이나 배치(Batch) 노드에는 비용이 최대 90% 저렴한 Spot Instance 사용을 우선 고려하고, 일반 컴퓨팅 워크로드에는 가성비가 높은 ARM 기반의 Graviton 프로세서 도입을 제안하십시오.
- **[PREFER] Storage Tiering:** S3 버킷 설계 시 intelligent-tiering 클래스를 적용하거나, 장기 보관 목적의 데이터는 Glacier 등으로 자동 전송되도록 수명 주기(Lifecycle) 정책을 정의하십시오.
- **[PREFER] EBS Optimization:** EC2 EBS 볼륨 제안 시 일반적인 워크로드 기준 가성비가 우수한 `gp3` 볼륨 타입을 기본값으로 기재하십시오.

### 2.2 네트워크 요금 회피
- **[MUST] NAT Gateway Avoidance:** S3, DynamoDB 등 트래픽 처리가 대량으로 발생하는 AWS 서비스와의 통신은 NAT Gateway 요금 폭증을 피하기 위해 VPC Endpoint(Gateway/Interface)를 구성하여 내부 인터넷 경로로 데이터를 격리하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- "최초 구축 시에는 T3/T4g 인스턴스를 활용하고, 트래픽 패턴에 맞추어 Auto Scaling Group(ASG)을 통해 자원을 유동적으로 확보하십시오."
- "EBS 볼륨 타입을 gp3로 선언하고 처리량(throughput) 및 IOPS를 필요 사양에 맞춰 수동 최적화하십시오."
</example>
<example>
[Bad]
- "트래픽 예측이 불가능하므로 초기부터 m5.4xlarge 인스턴스 10대를 상시 가동 상태로 띄우겠습니다."
- "EBS 볼륨은 gp2 볼륨 타입을 기본으로 유지하겠습니다."
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 리소스 생성 전/후의 예상 비용 변화가 수치로 확인되고, 완화 내역을 포함한 `finops-cost-report.md` 작성이 완료되어야 합니다.
- **[MUST] 검증 도구 매핑:** `infracost`가 로컬에 설치되어 있으면 `infracost` CLI를 활용하여 수정된 코드의 월별 예상 비용 증감을 실제로 검증하십시오. 미설치 환경에서는 [AWS Pricing Calculator](https://calculator.aws/)(혹은 유사 도구)를 사용하여 수동 코스트 추정을 `finops-cost-report.md`에 명시하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Resource Sizing] 도메인 자가 채점:** 인스턴스 타입, 개수, 디스크 용량 등 리소스 용량 설정을 기획하거나 수정할 때, 스스로 `<self_critique>` 태그를 열어 아래 2가지 점검 기준으로 1~5점 채점을 수행하고 사유를 명시하십시오. (두 기준 모두 5점 만점일 경우에만 작업을 승인 요청하십시오)
  - 기준 1 (과다 설계 배제): 현재 비즈니스 목표 대비 과도한 인프라 등급(instance type 등)이 지정되지 않았는가?
  - 기준 2 (탄력성 설계): 트래픽 오프피크(off-peak) 타임 시 리소스를 자동으로 내릴 수 있는 Auto Scaling 아키텍처가 결합되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - `infracost` 분석 결과, 단일 작업으로 인해 예상 월별 인프라 비용이 기존 대비 50% 이상 폭증(Drift)하는 현상이 감지될 경우 즉시 작업을 중단하고 비용 위반 보고서를 작성하십시오.
  - 사용하지 않는 고성능 NAT Gateway가 2개 이상 방치되거나 VPC Endpoint가 누락되어 요금이 낭비되는 설계가 확인될 시 작업을 멈추고 대체 경로를 수립하십시오.

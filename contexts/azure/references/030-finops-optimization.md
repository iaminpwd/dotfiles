---
role: Senior Cloud Architect
priority: high
trigger: Apply these rules ONLY when designing Azure infrastructure, provisioning resources, or optimizing cloud costs.
references:
  - contexts/azure/references/010-azure-core.md
reviewed: 2026-07-21
---
# 컨텍스트 모듈: FinOps 및 비용 최적화 (Cost Optimization)

본 모듈은 Azure 인프라 설계, 리소스 프로비저닝 및 클라우드 아키텍처 수명 주기 전반에 적용되는 비용 최적화 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Right-Sizing:** 모든 컴퓨팅/스토리지 자원은 실제 요구 트래픽에 맞춰 VM Scale Sets(VMSS)나 탄력적 용량(Spot 등)으로 사이징하십시오.
- **[MUST] Anomaly Detection:** 인프라 설계 시 예기치 못한 비용 폭증을 방지하기 위해 Azure Budgets 또는 Cost Management 비용 이상 탐지(Anomaly Detection) 알람 설정을 필수로 반영하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 컴퓨팅 및 스토리지 최적화
- **[PREFER] Graviton & Spot:** 비프로덕션 환경이나 배치(Batch) 노드에는 비용이 최대 90% 저렴한 Spot Virtual Machines 사용을 우선 고려하고, 일반 컴퓨팅 워크로드에는 가성비가 높은 ARM 기반의 Ampere Altra 프로세서 도입을 제안하십시오.
- **[MUST] Committed Use Discounts:** 트래픽이 안정적으로 예측 가능한 프로덕션 상시 가동 베이스라인 워크로드에는 Azure Reserved VM Instances 또는 Azure Savings Plan for Compute를 적용하여 온디맨드 대비 비용을 절감하십시오. Spot(변동성 큰 비프로덕션/배치용)과 Reserved/Savings Plan(예측 가능한 프로덕션 베이스라인용)은 대체재가 아닌 상호 보완 전략으로 함께 적용하십시오.
- **[PREFER] Storage Tiering:** Azure Blob Storage 설계 시, 장기 보관 목적의 데이터는 수명 주기(Lifecycle) 정책을 정의하여 Hot에서 Cool/Archive 계층으로 자동 전송되도록 하십시오.
- **[PREFER] Managed Disk Optimization:** VM 관리형 디스크 제안 시 일반적인 워크로드 기준 가성비가 우수한 `Standard SSD` 또는 `Premium SSD v2` 디스크 타입을 기본값으로 기재하십시오.

### 2.2 네트워크 요금 회피
- **[MUST] NAT Gateway Avoidance:** Blob Storage, Cosmos DB 등 데이터 전송이 대량으로 발생하는 Azure 서비스와의 통신은 NAT Gateway 요금 폭증을 피하기 위해 Private Endpoint(Private Link) 또는 Service Endpoint를 구성하여 내부 인터넷 경로로 데이터를 격리하십시오.

### 2.3 구버전 연장 지원(Extended Support/LTS) 요금 회피
- **[MUST] Explicit Fact-Check (버전 관리형 서비스 전수조사):** AKS, Azure Database for MySQL/PostgreSQL 등 **'엔진 버전(Version) 지정이 필요한 모든 Azure 관리형 서비스'**를 설계할 때, 해당 서비스에 Extended Support 또는 LTS(Long Term Support) 과금 정책이 존재하는지 웹 검색(`search_web`)으로 먼저 조사하십시오.
- **[MUST] Use Verified Latest Version:** 연장 지원 또는 LTS 과금 정책이 존재하는 서비스임이 확인되면, 학습 데이터의 기억에 의존하지 말고 **직전 단계에서 수행한 웹 검색 결과(또는 버전 확정을 위한 추가 웹 검색 결과)를 근거로** '현재 시간 기준' Azure 표준 지원(Standard Support)이 유효한 최신 안정화 버전을 코드에 반영함으로써 구버전으로 인한 숨은 비용을 차단하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- "최초 구축 시에는 B-series(Burstable) 인스턴스를 활용하고, 트래픽 패턴에 맞추어 Virtual Machine Scale Sets(VMSS)를 통해 자원을 유동적으로 확보하십시오."
- "관리형 디스크 타입을 Standard SSD로 선언하여 디스크 입출력 비용을 최적화하십시오."
- "AKS 버전을 지정하기 전 `search_web`으로 '현재 날짜 기준' Azure AKS 표준 지원 버전을 검색하여, LTS 추가 요금이 발생하지 않는 최신 안정 버전인 `1.XX`(검색 결과 반영) 버전으로 클러스터를 설정합니다." (예시의 버전을 그대로 복사하지 않고 검색된 최신 버전 대입)
</example>
<example>
[Bad]
- "트래픽 예측이 불가능하므로 초기부터 D16s_v5 인스턴스 10대를 상시 가동 상태로 띄우겠습니다."
- "EBS 볼륨에 해당하는 디스크는 무조건 Premium SSD(LRS) 타입을 기본으로 가겠습니다."
- "가장 익숙하거나 이전 프로젝트에서 썼던 구버전(예: AKS 1.25 등)을 팩트 체크 없이 그대로 하드코딩하여 설정하겠습니다." (검색 절차 누락 및 구버전 지정으로 인한 Extended Support/LTS 요금 발생 위반)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 리소스 생성 전/후의 예상 비용 변화가 수치로 확인되고, 완화 내역을 포함한 `finops-cost-report.md` 작성이 완료되어야 합니다.
- **[MUST] 검증 도구 매핑:** `infracost`가 로컬에 설치되어 있으면 `infracost` CLI를 활용하여 수정된 코드의 월별 예상 비용 증감을 검증하십시오. 미설치 환경에서는 [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/)(혹은 유사 도구)를 사용하여 수동 코스트 추정을 `finops-cost-report.md`에 명시하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Resource Sizing] 점검 기준 (절차는 010-azure-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (과다 설계 배제): 현재 비즈니스 목표 대비 과도한 인프라 등급(VM size 등)이 지정되지 않았는가?
  - 기준 2 (탄력성 설계): 트래픽 오프피크(off-peak) 타임 시 리소스를 자동으로 내릴 수 있는 Scale Sets 아키텍처가 결합되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - `infracost` 분석 결과, 단일 작업으로 인해 예상 월별 인프라 비용이 기존 대비 50% 이상 폭증(Drift)하는 현상이 감지될 경우 즉시 작업을 중단하고 비용 위반 보고서를 작성하십시오.
  - 사용하지 않는 NAT Gateway가 2개 이상 방치되거나 Private Endpoint가 누락되어 요금이 낭비되는 설계가 확인될 시 작업을 멈추고 대체 경로를 수립하십시오.

---
role: Senior OpenStack Architect
priority: high
trigger: Apply these rules ONLY when designing OpenStack infrastructure, provisioning resources, or optimizing private cloud capacity and cost.
references:
  - contexts/openstack/references/010-openstack-core.md
reviewed: 2026-07-23
---
# 컨텍스트 모듈: FinOps 및 용량·비용 최적화 (Cost Optimization)

본 모듈은 OpenStack 프라이빗 클라우드 설계, 리소스 프로비저닝 및 수명 주기 전반에 적용되는 용량·비용 최적화 표준 가이드라인입니다. 프라이빗 클라우드 비용은 물리 하드웨어 집적도, 쿼터 통제, 자원 회수, 차지백(Chargeback)으로 관리됩니다.

## 1. 핵심 설계 원칙
- **[MUST] Right-Sizing (Flavor):** 모든 인스턴스는 실제 요구 사양에 맞는 최소 Flavor로 사이징하고, 과도한 오버프로비저닝을 피하십시오. 부하 변동은 Heat/Senlin 오토스케일링 그룹으로 흡수하십시오.
- **[MUST] Quota Guardrails:** 프로젝트별 쿼터(cores, RAM, instances, volumes, floating IP)를 명시적으로 설정하여 특정 테넌트의 자원 독점과 하이퍼바이저 고갈을 사전 차단하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 컴퓨팅 및 스토리지 최적화
- **[PREFER] Overcommit & Host Aggregate:** CPU/RAM overcommit 비율을 워크로드 특성별로 분리하고, 성능 민감 워크로드는 전용 Host Aggregate/AZ로 격리하여 노이지 네이버(noisy neighbor)를 방지하십시오.
- **[PREFER] Reclaim Orphaned Resources:** 미연결(unattached) Cinder 볼륨, 미할당(unassociated) floating IP, 방치된 스냅샷은 프라이빗 클라우드의 대표적 낭비 요인이므로 주기적으로 조회하여 회수하십시오.
- **[PREFER] Storage Tiering:** Cinder 볼륨 타입을 성능 등급(SSD/HDD 백엔드)별로 분리하고, 콜드 데이터는 저비용 백엔드 또는 Swift 객체 스토리지로 이관하는 수명 주기 정책을 정의하십시오.
- **[PREFER] Ceph Efficiency:** Ceph 백엔드 사용 시 replica 3 대비 용량 효율이 높은 Erasure Coding을 콜드/객체 풀에 적용하고, thin provisioning 대비 실제 사용량을 상시 모니터링하십시오.
- **[PREFER] Continuous Right-Sizing:** 배포 직후 사양 산정에 그치지 말고, Ceilometer/Gnocchi의 실사용 CPU/메모리 지표 기반으로 Flavor와 볼륨 사양을 주기적으로 재조정하십시오.

### 2.2 차지백 및 미터링
- **[PREFER] Chargeback/Showback:** 테넌트별 자원 사용량 과금·정산이 필요하면 CloudKitty를 도입하여 Ceilometer/Gnocchi 미터링 데이터 기반 rating 정책으로 프로젝트별 비용을 산출하십시오.
- **[MUST] Anomaly Awareness:** 예기치 못한 자원 폭증을 방지하기 위해 Aodh 알람으로 프로젝트 쿼터 사용률 임계치(예: 80%) 초과 시 경보를 발송하도록 설계하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- "최초 구축 시 소형 Flavor(m1.small)로 시작하고, 트래픽 패턴에 맞춰 Senlin/Heat ASG로 자원을 유동적으로 확보하십시오."
- "미할당 floating IP를 `openstack floating ip list --status DOWN`으로 조회하여 회수하고, 미연결 볼륨을 `openstack volume list --status available`로 정리하십시오."
</example>
<example>
[Bad]
- "트래픽 예측이 불가능하므로 초기부터 대형 Flavor 인스턴스 10대를 상시 가동 상태로 띄우겠습니다."
- "볼륨과 floating IP는 사용이 끝나도 그냥 두겠습니다." (자원 누수 및 쿼터 고갈)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 리소스 생성 전/후의 예상 자원 소비 변화(cores/RAM/볼륨)가 수치로 확인되고, 완화 내역을 포함한 `finops-cost-report.md` 작성이 완료되어야 합니다.
- **[MUST] 검증 도구 매핑:** `openstack quota show <project>` 및 `openstack limits show --absolute`로 잔여 용량 대비 신규 소비를 실제로 검증하십시오. 차지백 정산이 필요하면 CloudKitty rating 결과를 `finops-cost-report.md`에 명시하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Resource Sizing] 점검 기준 (절차는 010-openstack-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (과다 설계 배제): 현재 비즈니스 목표 대비 과도한 Flavor 등급이 지정되지 않았는가?
  - 기준 2 (탄력성 설계): 트래픽 오프피크(off-peak) 시 인스턴스를 자동으로 축소할 수 있는 오토스케일링 아키텍처가 결합되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 단일 작업으로 인해 프로젝트 쿼터 또는 하이퍼바이저 잔여 용량의 50% 이상이 일시에 소진되는 사양이 감지될 경우 즉시 작업을 중단하고 용량 위반 보고서를 작성하십시오.
  - 미연결 볼륨/미할당 floating IP가 다량 방치되어 쿼터가 낭비되는 설계가 확인될 시 작업을 멈추고 회수 계획을 수립하십시오.

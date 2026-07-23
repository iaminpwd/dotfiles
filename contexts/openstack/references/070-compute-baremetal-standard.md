---
role: Senior OpenStack Architect
priority: high
trigger: Apply these rules ONLY when working with Nova compute (flavors, host aggregates, live migration) or Ironic bare metal provisioning.
references:
  - contexts/openstack/references/050-iac-standard.md
  - contexts/openstack/references/020-security-compliance.md
  - contexts/openstack/references/025-cloud-security.md
  - contexts/openstack/references/030-finops-optimization.md
reviewed: 2026-07-23
---
# 컨텍스트 모듈: Nova 컴퓨트 및 Ironic 베어메탈 표준

본 모듈은 Nova 하이퍼바이저/인스턴스 스케줄링과 Ironic 베어메탈 프로비저닝 설계·운영 시 적용되는 기술 표준 가이드라인입니다. (퍼블릭 클라우드가 추상화하는 하이퍼바이저·물리 노드 계층을 직접 관장하는 OpenStack 고유 영역입니다.)

## 1. 핵심 설계 원칙
- **[MUST] Scheduling Isolation:** 워크로드 특성(성능 민감/일반/베어메탈)에 따라 Host Aggregate와 Availability Zone으로 스케줄링을 격리하고, `flavor` extra_specs(`aggregate_instance_extra_specs`, `trait:`)로 배치 제약을 명시하십시오.
- **[MUST] Anti-Affinity for HA:** 동일 서비스의 복제 인스턴스는 Server Group `anti-affinity` 정책으로 서로 다른 하이퍼바이저에 분산 배치하여 단일 물리 노드 장애의 영향을 차단하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 Nova 컴퓨트 및 하이퍼바이저
- **[MUST] Overcommit Control:** CPU/RAM overcommit 비율을 Host Aggregate 단위로 분리 설정하고, 성능 민감 워크로드에는 `hw:cpu_policy=dedicated`(CPU 피닝)를 적용하여 노이지 네이버를 방지하십시오.
- **[MUST] Safe Live Migration:** 하이퍼바이저 유지보수 시 `openstack server migrate --live-migration`으로 인스턴스를 비우고, 마이그레이션 전 대상 호스트 용량과 공유 스토리지(Ceph/NFS) 연결을 사전 검증하십시오.
- **[PREFER] Image Standardization:** 부팅 이미지는 Glance에 표준 골든 이미지로 관리하고, `cloud-init`로 초기 구성을 주입하며 이미지 서명(signature)을 검증하십시오. Ceph를 Glance/Nova 백엔드로 사용하는 경우 copy-on-write 클론이 동작하도록 이미지를 `raw` 포맷으로 저장하여 qcow2 변환으로 인한 부팅 지연·용량 폭증을 방지하십시오.

### 2.2 Ironic 베어메탈
- **[MUST] Node Cleaning:** 베어메탈 노드 회수 시 반드시 자동 클리닝(automated cleaning: 디스크 소거)을 활성화하여 이전 테넌트 데이터 잔존을 차단하십시오.
- **[MUST] Isolated Provisioning Network:** PXE/프로비저닝 트래픽은 tenant 네트워크와 분리된 전용 provisioning network로 격리하고, BMC(IPMI/Redfish) 관리 대역을 별도 보안 세그먼트로 통제하십시오.
- **[PREFER] Boot Mode:** 신규 하드웨어는 Legacy BIOS 대신 UEFI + Secure Boot를 우선 적용하여 부팅 체인 무결성을 확보하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- HA 분산: "웹 인스턴스 3대는 Server Group `anti-affinity`로 생성하여 서로 다른 하이퍼바이저에 배치하십시오."
- 베어메탈 회수: "노드 반납 전 `openstack baremetal node manage` 후 automated cleaning으로 디스크를 소거하십시오."
</example>
<example>
[Bad]
- 단일 노드 집중: "웹 인스턴스 3대를 affinity로 묶어 한 하이퍼바이저에 몰아넣겠습니다." (단일 장애점)
- 클리닝 생략: "베어메탈 노드를 클리닝 없이 바로 다음 테넌트에 재할당하겠습니다." (데이터 잔존)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** Flavor extra_specs·Server Group 정책·Aggregate 매핑이 IaC에 누락 없이 선언되고, 베어메탈 노드의 클리닝/프로비저닝 네트워크 격리가 검증되어야 합니다.
- **[MUST] 검증 도구 매핑:** `openstack hypervisor stats show`로 잔여 용량을, `openstack server group list`로 배치 정책을, `openstack baremetal node list`로 노드 상태를 기계적으로 확인하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Compute/Baremetal Provisioned] 점검 기준 (절차는 010-openstack-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (가용성): 동일 서비스 복제본이 anti-affinity 또는 다중 Aggregate/AZ로 물리 분산되었는가?
  - 기준 2 (격리): 베어메탈 프로비저닝/BMC 대역이 tenant 트래픽과 분리되어 있는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 하이퍼바이저 잔여 용량을 초과하는 인스턴스 부팅이 시도되어 스케줄링 실패(No valid host)가 예상될 시 즉시 작업을 중단(Halt & Clarify)하고 용량 확보를 요청하십시오.
  - 베어메탈 노드가 automated cleaning 없이 재프로비저닝되도록 설계되어 이전 테넌트 데이터 잔존 위험이 감지되면 작업을 즉시 멈추고 보안 수정을 강제(Hard Block)하십시오.

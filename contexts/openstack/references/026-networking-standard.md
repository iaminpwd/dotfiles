---
role: Senior OpenStack Architect
priority: high
trigger: Apply these rules ONLY when designing Neutron network architecture, SDN backends (OVN/ML2), or tenant/provider networks.
references:
  - contexts/openstack/references/010-openstack-core.md
  - contexts/openstack/references/025-cloud-security.md
---
# 컨텍스트 모듈: Neutron 네트워크 아키텍처 표준

본 모듈은 OpenStack Neutron의 SDN 백엔드 선택, tenant/provider 네트워크 토폴로지 및 라우팅 아키텍처 설계 시 적용되는 기술 표준 가이드라인입니다. 네트워크 보안(보안 그룹/FWaaS)은 `025-cloud-security.md`를 참조하십시오.

## 1. 핵심 설계 원칙
- **[MUST] SDN Backend Selection:** 신규 배포는 OVN(`ovn` ML2 드라이버)을 기본으로 채택하고, 레거시 OVS/ML2 + L3 agent 조합은 기존 환경 유지보수 목적에만 사용하십시오. 선택 근거(에이전트 수, 분산 라우팅 지원, 커뮤니티 방향성)를 명시하십시오.
- **[MUST] Tenant/Provider 분리:** tenant 오버레이(VXLAN/GENEVE)와 provider(VLAN/flat) 네트워크의 역할을 분리하고, 외부 연결은 provider network + 라우터 external gateway로만 노출하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)
- **[MUST] Encapsulation & MTU:** 오버레이 캡슐화 오버헤드(VXLAN 50B, GENEVE 38B 이상)를 고려해 물리 MTU(jumbo frame 9000 권장)와 tenant network MTU를 정합적으로 설정하여 파편화·성능 저하를 방지하십시오.
- **[PREFER] Distributed Routing:** 남북/동서 트래픽 병목을 줄이기 위해 OVN 분산 라우팅(또는 OVS DVR)을 활성화하되, floating IP 트래픽이 중앙 게이트웨이 노드에 집중되지 않는지 검토하십시오.
- **[MUST] Address Management:** tenant CIDR 중복과 고갈을 막기 위해 subnet pool + address scope로 IP 할당을 중앙 관리하고, 외부 라우팅 대상 대역은 별도 scope로 격리하십시오.
- **[PREFER] QoS Isolation:** 특정 테넌트의 대역 독점을 막기 위해 Neutron QoS policy(대역폭 제한/DSCP)를 적용하십시오.
- **[MUST] Agent/Chassis HA:** L3/DHCP agent(OVS) 또는 gateway chassis(OVN)를 다중화하고, `openstack network agent list`로 에이전트 alive 상태를 상시 검증하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- "물리 NIC MTU를 9000으로 설정하고 GENEVE tenant network MTU를 8942 이하로 지정하여 캡슐화 오버헤드를 흡수하십시오."
- "OVN gateway chassis를 2개 이상 지정하여 floating IP 라우팅의 단일 장애점을 제거하십시오."
</example>
<example>
[Bad]
- "물리 MTU 1500 위에 VXLAN tenant network MTU를 1500으로 설정합니다." (오버헤드 미반영 → 파편화)
- "L3 agent를 컨트롤러 1대에만 두어 전 tenant 라우팅을 집중시킵니다." (단일 장애점)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** network type, MTU, 라우팅 모드(분산/중앙), 에이전트 이중화 구성이 IaC에 명시되고 검증되어야 합니다.
- **[MUST] 검증 도구 매핑:** `openstack network agent list`(alive 상태), `openstack network show <net>`(mtu/type), `openstack subnet pool list`(중앙 IP 관리)로 실제 구성을 기계적으로 확인하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Network Topology Designed] 점검 기준 (절차는 010-openstack-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (MTU 정합성): 물리 MTU가 tenant MTU + 캡슐화 오버헤드를 수용하도록 정합적으로 설계되었는가?
  - 기준 2 (라우팅 이중화): 라우팅/게이트웨이가 다중화되어 단일 장애점이 제거되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 물리 MTU가 tenant MTU + 캡슐화 오버헤드보다 작아 상시 패킷 파편화·성능 저하가 예상되는 설정이 감지되면 즉시 작업을 중단(Halt & Clarify)하고 MTU 재설계를 요청하십시오.

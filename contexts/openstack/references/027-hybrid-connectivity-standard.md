---
role: Senior OpenStack Architect
priority: high
trigger: Apply these rules ONLY when designing hybrid/edge connectivity — VPNaaS, dynamic routing (BGP), external interconnect, or identity federation.
references:
  - contexts/openstack/references/010-openstack-core.md
  - contexts/openstack/references/025-cloud-security.md
  - contexts/openstack/references/026-networking-standard.md
reviewed: 2026-07-23
---
# 컨텍스트 모듈: 하이브리드 연결성 및 엣지 표준

본 모듈은 OpenStack을 온프렘/퍼블릭 클라우드/엣지와 연결하는 사이트 간 상호 연동(interconnect), 동적 라우팅 및 아이덴티티 페더레이션 설계 시 적용되는 기술 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Encrypted Interconnect:** 온프렘/퍼블릭 클라우드와의 사이트 간 연결은 Neutron VPNaaS(IPsec site-to-site) 또는 전용 회선 위 암호화 터널로만 구성하고, 구간 전체에 IPsec/TLS 암호화를 적용하십시오.
- **[MUST] Non-overlapping CIDR:** 연결 대상 간 CIDR 충돌을 사전 조사하여 겹치지 않게 설계하고, 불가피한 경우 NAT로 주소 공간을 격리하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)
- **[MUST] Dynamic Routing:** 다중 경로/대규모 연동은 정적 라우트 남발 대신 `neutron-dynamic-routing`(BGP speaker)으로 tenant/provider 대역을 광고하여 라우팅 확장성을 확보하십시오.
- **[MUST] Identity Federation:** 조직 간 워크로드 연동 시 자격 증명을 복제하지 말고, Keystone-to-Keystone(K2K) 또는 OIDC/SAML 페더레이션으로 신뢰를 위임하여 단기 페더레이션 토큰을 사용하십시오.
- **[PREFER] Edge/DCN:** 지연에 민감한 엣지 워크로드는 분산 컴퓨트 노드(DCN) 아키텍처로 로컬에서 처리하고, 컨트롤플레인과의 WAN 의존을 최소화하십시오.
- **[MUST] Multi-cloud Delegation:** 특정 퍼블릭 클라우드 리소스와의 상세 연동 설계는 `~/dotfiles/contexts/multi-cloud/SKILL.md`를 참조하여 크로스 벤더 규칙을 확보하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- "온프렘 데이터센터 연결은 IPsec site-to-site(VPNaaS)로 구성하고, PSK 대신 인증서 기반 IKEv2를 적용하십시오."
- "다수 tenant 대역 광고는 BGP speaker로 자동화하고, 광고 대상 대역을 address scope로 한정하십시오."
</example>
<example>
[Bad]
- "온프렘과 GRE 평문 터널로 연결하고 암호화는 나중에 붙이겠습니다." (전송 구간 노출)
- "양쪽 사이트 모두 10.0.0.0/16을 사용하지만 그냥 연결하겠습니다." (CIDR 중첩 라우팅 파손)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 터널 암호화, CIDR 비중첩(또는 NAT 격리), 라우팅 광고 범위가 명시되고 검증되어야 합니다.
- **[MUST] 검증 도구 매핑:** `openstack vpn ipsec site connection list`(터널 상태), `openstack bgp speaker list`(라우팅 광고), CIDR 중첩 여부를 `openstack subnet list`로 기계적으로 확인하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Interconnect Designed] 점검 기준 (절차는 010-openstack-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (전송 암호화): 사이트 간 전 구간이 IPsec/TLS로 암호화되었는가?
  - 기준 2 (주소 무결성): 연결 대상 간 CIDR가 비중첩이거나 NAT로 격리되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 사이트 간 트래픽이 암호화 없이 평문으로 전달되도록 설계된 인터커넥트가 감지되면 즉시 작업을 중단(Hard Block)하고 보안 경고를 발송하십시오.
  - 연결 대상 간 CIDR가 중첩되어 라우팅이 파손될 설계가 확인되면 작업을 멈추고(Halt & Clarify) 대역 재설계 또는 NAT 격리를 요청하십시오.

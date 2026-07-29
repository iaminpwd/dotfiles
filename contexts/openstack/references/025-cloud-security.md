---
role: Senior OpenStack Architect
priority: high
trigger: Apply these rules ONLY when designing private cloud network architecture, container deployments, or enterprise multi-project/multi-domain environments.
references:
  - contexts/openstack/references/020-security-compliance.md
  - contexts/openstack/references/010-openstack-core.md
  - contexts/openstack/references/030-finops-optimization.md
---
# 컨텍스트 모듈: 클라우드 인프라 및 네트워크 보안 (Cloud Security)

해당 도메인 설계 및 작업 시 적용되는 표준임.

## 1. 핵심 설계 원칙
- **[MUST] Zero-Trust 기반 인그레스 통제 (Default Deny):** Octavia LB의 웹 포트(80, 443) 외 기타 모든 포트(SSH, DB, Redis, 내부 API 등)의 인그레스는 사내 VPN CIDR 대역(예: `10.10.0.0/16`) 또는 특정 원격 보안 그룹(remote group)으로만 격리할 것.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 네트워크 및 엣지 보안
- **[MUST] IaC 레벨의 CIDR 유효성 검증:** 웹 서비스 목적 외의 모든 포트 CIDR 변수 입력 시, 값이 `0.0.0.0/0`이면 보안 규정 위반 에러를 출력하고 배포를 중단시키는 `validation` 블록을 Terraform에 필수 기재할 것. 웹 포트 외 포트에 전역 개방이 필요하면 VPN 대역으로 대상을 한정하거나 사내 보안 규정 검증 절차를 거치십시오.
- **[MUST] FWaaS / Router 통제:** tenant 간 경계에는 Neutron FWaaS v2 정책을 적용하고, 외부 게이트웨이(external gateway)를 갖는 라우터에는 불필요한 인바운드 라우트가 없는지 검증할 것.
- **[MUST] SSH via Bastion:** 인스턴스 직접 SSH 노출을 격리하고, floating IP를 붙인 전용 Bastion 또는 VPN을 경유하도록 설계를 제안할 것.
- **[PREFER] Provider Network 격리:** 관리(management)·스토리지(Ceph)·tenant 트래픽을 별도 provider network/VLAN으로 분리하여 컨트롤플레인과 데이터플레인 노출을 안전하게 격리할 것.

### 2.2 엔터프라이즈 권한 통제
- **[MUST] Domain/Project 격리:** 신규 멀티테넌트 환경 구축 시 조직 단위로 Keystone Domain을 분리하고, 워크로드는 Project 단위로 최소 분할하여 쿼터와 역할을 격리 설계할 것.
- **[PREFER] Federation (SSO):** 다중 조직 접근 통제를 위해 Keystone Federation(OIDC/SAML) 기반 중앙 집중형 연동 아키텍처를 최우선 제안할 것.
- **[PREFER] Policy-as-Code:** Keystone `policy.yaml`(oslo.policy) 커스터마이징 시 기본 정책보다 완화되지 않도록 검토하고, 변경은 코드로 버전 관리할 것.
- **[PREFER] Audit Trail:** 컨트롤플레인 API 감사를 위해 CADF 기반 감사 로그(Keystone/Nova audit middleware)를 활성화하여 접근 이력을 상시 기록할 것.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- "DB 보안 그룹의 3306 포트 인그레스를 애플리케이션 보안 그룹(remote group `sg-app`)만을 명시적으로 허용할 것."
- "SSH 22번 포트 인그레스 소스를 사내 VPN 대역(`10.10.0.0/16`)으로만 한정할 것."
</example>
<example>
[Bad]
- "DB 보안 그룹 3306 포트를 `0.0.0.0/0`으로 엽니다."
- "SSH 포트를 `0.0.0.0/0`으로 임시 개방함."
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 탐지된 취약점은 무결하게 해결해야 합니다.
  - **감사 보고서:** 포트 추가/삭제, 보안 그룹 신규 생성 등 중대한 변경이 발생할 경우에만 `security-audit-report.md`를 작성할 것.
## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Network Rule Modified] 점검 기준 (절차는 010-openstack-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (포트 격리): 대국민 서비스 웹 포트(80/443) 이외의 모든 타겟 포트 인그레스가 `0.0.0.0/0` 없이 VPN 대역 또는 원격 보안 그룹으로만 격리되었는가?
  - 기준 2 (경계 통제): FWaaS/router 정책을 통해 tenant 간 트래픽이 승인된 경로로만 라우팅되도록 통제되는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - floating IP를 갖는 인스턴스의 22(SSH) 또는 3389(RDP) 포트가 `0.0.0.0/0`으로 개방되어 배포 준비가 된 코드가 감지되면 즉시 작업을 중단(Hard Block)하고 경고할 것.
  - 포트 시큐리티가 비활성화(`port_security_enabled = false`)되어 스푸핑 방어가 제거된 설정이 감지되면 작업을 즉시 중단할 것.

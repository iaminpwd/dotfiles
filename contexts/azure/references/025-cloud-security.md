---
role: Senior Cloud Architect
priority: high
trigger: Apply these rules ONLY when designing cloud network architecture, container deployments, or enterprise multi-account environments.
references:
  - contexts/azure/references/020-security-compliance.md
  - contexts/azure/references/010-azure-core.md
  - contexts/azure/references/030-finops-optimization.md
---
# 컨텍스트 모듈: 클라우드 인프라 및 네트워크 보안 (Cloud Security)

본 모듈은 Azure 클라우드 네트워크 아키텍처 설계, 공급망 보안 및 엔터프라이즈 다중 구독 접근 통제 시 적용되는 보안 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Assume Breach:** 모든 네트워크 트래픽은 이미 침해되었다고 가정하고 설계하십시오. VNet 및 인스턴스 간 통신 시 네트워크 보안 그룹(NSG)의 인바운드/아웃바운드를 최소 권한으로 구성하십시오.
- **[MUST] Zero-Trust 기반 인바운드 통제 (Default Deny):** Public Application Gateway나 Azure Front Door의 웹 포트(80, 443) 외 기타 모든 포트(SSH, DB, Redis, 내부 API 등)의 인바운드는 사내 VPN IP 대역(예: `10.32.0.0/16`) 또는 특정 애플리케이션 보안 그룹(ASG)으로만 격리하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 네트워크 및 엣지 보안
- **[MUST] IaC 레벨의 CIDR 유효성 검증:** 웹 서비스 목적 외의 모든 포트 CIDR 블록 변수 입력 시, 값이 `0.0.0.0/0`이면 보안 규정 위반 에러를 출력하고 배포를 중단시키는 `validation` 블록을 Terraform에 필수로 기재하십시오. 웹 포트 외의 포트에 0.0.0.0/0이 할당될 경우, VPN 대역으로 대상을 한정하거나 사내 보안 규정 검증 절차를 필히 거치십시오.
- **[PREFER] WAF/DDoS:** 퍼블릭 엔드포인트(Application Gateway, Azure Front Door) 제안 시 Azure WAF와 Azure DDoS Protection 적용을 포함하십시오.
- **[MUST] Bastion:** 인스턴스 직접 SSH 접근을 차단하고, Azure Bastion을 통하도록 설계를 제안하십시오.
- **[MUST] Private Endpoint:** Azure 내부 서비스 통신 시 퍼블릭 인터넷 경로 노출을 차단하기 위해 Private Endpoint(Private Link)를 구성하십시오.
- **[MUST] Data in Transit:** 모든 클라우드 내부 및 외부 네트워크 통신에 TLS 암호화를 적용하십시오.

### 2.2 엔터프라이즈 권한 통제
- **[MUST] Federation (SSO):** 다중 구독 접근 통제를 위해 Microsoft Entra ID (SSO) 기반의 중앙 집중형 연동 아키텍처를 최우선 제안하십시오.
- **[PREFER] Threat Detection:** 엔터프라이즈 내부 네트워크 위협 탐지를 위해 Microsoft Defender for Cloud 적용을 함께 제안하십시오.
- **[PREFER] Policy/RBAC:** 다중 구독 설계 시 Azure Management Groups의 Azure Policy 및 Azure RBAC를 활용하여 최대 권한 범위를 강제 제한하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- "DB Network Security Group(NSG)의 3306 포트 인바운드를 애플리케이션 보안 그룹(ASG)으로만 제한하십시오."
- "SSH 접근을 위한 22번 포트 인바운드 소스를 사내 VPN 대역(`10.32.0.0/16`)으로만 한정하십시오."
</example>
<example>
[Bad]
- "DB NSG 3306 포트를 `0.0.0.0/0`으로 엽니다."
- "SSH 포트를 `0.0.0.0/0`으로 임시 개방합니다."
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** `pre-flight-check.sh` 스캔을 통해 탐지된 네트워크 취약점이나 노출 포트가 무결하게 해결되고, 완화 내역을 포함한 `security-audit-report.md`가 작성되어야 합니다.
- **[MUST] 검증 도구 매핑:** `tfsec` 또는 `checkov`를 사용하여 IaC 파일 내의 NSG 광대역 오픈 및 암호화 누락을 자동 스캔하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Network Rule Modified] 도메인 자가 채점:** 네트워크 보안 그룹(NSG)이나 라우팅 테이블 설계를 제안/수정한 직후, 스스로 `<self_critique>` 태그를 열어 아래 2가지 점검 기준으로 1~5점 자가 채점을 수행하고 사유를 명시하십시오. (두 기준 모두 5점 만점일 때만 계획을 제안하십시오)
  - 기준 1 (포트 격리): 대국민 서비스 웹 포트(80/443) 이외의 타겟 포트가 `0.0.0.0/0`에 완전 개방되었는가?
  - 기준 2 (데이터 경로): Private Endpoint가 배제되어 Azure 내부 통신이 퍼블릭 인터넷 망을 타는 경로가 있는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 퍼블릭 IP를 갖는 VM 인스턴스의 22(SSH) 또는 3389(RDP) 포트가 `0.0.0.0/0`으로 개방되어 배포 준비가 된 코드가 감지되면 즉시 작업을 멈추고 Halt & Clarify 브리핑을 통해 경고하십시오.
  - 컨테이너 이미지 파이프라인에서 취약한 기본 이미지(CVE 크리티컬 레벨) 노출이 스캔 결과 감지되었으나 대체 이미지가 제안되지 않을 경우 작업을 즉시 중단하십시오.

---
role: Senior Cloud Architect
priority: high
trigger: Apply these rules ONLY when designing cloud network architecture, container deployments, or enterprise multi-account environments.
references:
  - contexts/aws/references/020-security-compliance.md
  - contexts/aws/references/010-aws-core.md
  - contexts/aws/references/030-finops-optimization.md
---
# 컨텍스트 모듈: 클라우드 인프라 및 네트워크 보안 (Cloud Security)

본 모듈은 AWS 클라우드 네트워크 아키텍처 설계, 공급망 보안 및 엔터프라이즈 다중 계정 접근 통제 시 적용되는 보안 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Zero-Trust 기반 인바운드 통제 (Default Deny):** Public ALB나 CloudFront의 웹 포트(80, 443) 외 기타 모든 포트(SSH, DB, Redis, 내부 API 등)의 인바운드는 사내 VPN IP 대역(예: `10.10.0.0/16`) 또는 특정 보안 그룹으로만 격리하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 네트워크 및 엣지 보안
- **[MUST] IaC 레벨의 CIDR 유효성 검증:** 웹 서비스 목적 외의 모든 포트 CIDR 블록 변수 입력 시, 값이 `0.0.0.0/0`이면 보안 규정 위반 에러를 출력하고 배포를 중단시키는 `validation` 블록을 Terraform에 필수로 기재하십시오. 웹 포트 외의 포트에 0.0.0.0/0이 할당될 경우, VPN 대역으로 대상을 한정하거나 사내 보안 규정 검증 절차를 필히 거치십시오.
- **[PREFER] WAF/Shield:** 퍼블릭 엔드포인트(ALB, CloudFront) 제안 시 AWS WAF와 Shield Advanced 적용을 포함하십시오.
- **[MUST] Session Manager:** 인스턴스 직접 SSH 접근을 차단하고, AWS SSM Session Manager를 통하도록 설계를 제안하십시오.
- **[MUST] VPC Endpoint:** AWS 내부 서비스 통신 시 퍼블릭 인터넷 경로 노출을 차단하기 위해 VPC Endpoint(Gateway/Interface)를 구성하십시오.
- **[PREFER] IPAM:** 멀티 VPC/멀티 계정 환경에서 CIDR 중복 할당을 방지하기 위해 Amazon VPC IP Address Manager(IPAM)를 통한 중앙 집중형 IP 주소 관리를 제안하십시오.

### 2.2 엔터프라이즈 권한 통제
- **[MUST] Landing Zone Structure:** 신규 멀티 계정 환경 구축 시 AWS Control Tower(또는 Landing Zone Accelerator)를 기반으로 Management, Log Archive, Security Tooling, 워크로드(Prod/Non-Prod) 계정을 최소 단위로 분리한 계정 구조를 우선 설계하십시오.
- **[PREFER] Federation (SSO):** 다중 계정 접근 통제를 위해 AWS IAM Identity Center (SSO) 기반의 중앙 집중형 연동 아키텍처를 최우선 제안하십시오.
- **[PREFER] Threat Detection:** 엔터프라이즈 내부 네트워크 위협 탐지를 위해 Amazon GuardDuty 적용을 함께 제안하십시오.
- **[PREFER] Continuous Compliance:** 리소스 설정 드리프트 상시 탐지를 위해 AWS Config Rules를, GuardDuty 등 여러 보안 서비스의 탐지 결과를 통합 관리하기 위해 AWS Security Hub를 함께 제안하십시오.
- **[PREFER] SCP/Boundary:** Organizations의 SCP 및 IAM Permission Boundary를 활용하여 멤버 계정의 최대 권한 범위를 강제 제한하십시오.
- **[PREFER] Vulnerability & Data Classification:** EC2/ECR/Lambda 워크로드의 알려진 CVE 취약점은 Amazon Inspector로 자동 스캔하고, S3에 저장된 민감 데이터(PII 등)는 Amazon Macie로 자동 분류 및 탐지하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- "DB 보안 그룹의 3306 포트 인바운드를 애플리케이션 보안 그룹 ID(`sg-xxxx`)로만 제한하십시오."
- "SSH 접근을 위한 22번 포트 인바운드 소스를 사내 VPN 대역(`10.10.0.0/16`)으로만 한정하십시오."
</example>
<example>
[Bad]
- "DB 보안 그룹 3306 포트를 `0.0.0.0/0`으로 엽니다."
- "SSH 포트를 `0.0.0.0/0`으로 임시 개방합니다."
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** `pre-flight-check.sh` 스캔을 통해 탐지된 네트워크 취약점이나 노출 포트가 무결하게 해결되어야 합니다. 포트 추가/삭제, SG 신규 생성 등 중대한 변경이 발생할 경우에만 완화 내역을 포함한 `security-audit-report.md`를 작성하십시오.
- **[MUST] 검증 도구 매핑:** `tfsec` 또는 `checkov`를 사용하여 IaC 파일 내의 보안 그룹 광대역 오픈 및 암호화 누락을 자동 스캔하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Network Rule Modified] 점검 기준 (절차는 010-aws-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (포트 격리): 대국민 서비스 웹 포트(80/443) 이외의 모든 타겟 포트 인바운드가 `0.0.0.0/0` 없이 VPN 대역 또는 특정 보안 그룹으로만 격리되었는가?
  - 기준 2 (데이터 경로): AWS 내부 서비스 통신이 VPC Endpoint를 경유하는 프라이빗 경로로만 구성되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 퍼블릭 IP를 갖는 EC2 인스턴스의 22(SSH) 또는 3389(RDP) 포트가 `0.0.0.0/0`으로 개방되어 배포 준비가 된 코드가 감지되면 즉시 작업을 중단(Hard Block)하고 경고하십시오.
  - 컨테이너 이미지 파이프라인에서 취약한 기본 이미지(CVE 크리티컬 레벨) 노출이 스캔 결과 감지되었으나 대체 이미지가 제안되지 않을 경우 작업을 즉시 중단하십시오.

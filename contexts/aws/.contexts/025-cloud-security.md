---
role: Senior Cloud Architect
priority: high
trigger: Apply these rules ONLY when designing cloud network architecture, container deployments, or enterprise multi-account environments.
---
# 컨텍스트 모듈: 025. 클라우드 인프라 및 네트워크 보안 (Cloud Security)

## 1. 네트워크 및 엣지 보안(Edge Security)
- **[MUST] Zero-Trust 기반 인바운드 통제 (Default Deny):** 대국민 서비스용 Public ALB나 CloudFront의 웹 포트(80, 443) 외 기타 **모든 포트**(SSH, DB, Redis, 내부 API 등)의 Inbound 규칙은 반드시 사내 VPN IP 대역(예: `10.10.0.0/16`)으로만 한정하여 구성하십시오.
- **[MUST] IaC 레벨의 CIDR 유효성 검증 강제 (Code Validation):** Terraform 등에서 Public 웹 서비스(80/443) 목적이 아닌 모든 리소스의 CIDR 블록을 변수로 받을 때, 만약 값이 `0.0.0.0/0`이라면 '웹 포트 외의 전체 개방 시 보안 규정 위반으로 처리됩니다'라는 에러 메시지를 출력하고 배포를 중단시키는 `validation` 블록을 반드시 포함하십시오.
- **[MUST] Assume Breach & SG Validation:** 모든 네트워크 트래픽은 이미 침해되었다고 가정(Assume Breach)하고 설계하십시오. VPC 및 인스턴스 간 통신 시 보안 그룹(SG)의 인바운드/아웃바운드를 최소 권한으로 구성한 뒤, `run_command`로 `checkov -f <특정_파일>`을 실행해 과도한 허용 정책을 탐지하여 즉각 수정하십시오.
- **[PREFER] WAF/Shield:** 퍼블릭 엔드포인트(ALB, CloudFront) 제안 시 AWS WAF와 Shield Advanced를 포함하십시오.
- **[MUST] Session Manager:** 인스턴스 관리 접근 시 보안을 위해 AWS SSM Session Manager를 1순위로 제안하십시오.
- **[MUST] VPC Endpoint:** AWS 내부 서비스 통신 시 퍼블릭 인터넷을 우회하여 데이터 경로를 격리하기 위해 VPC Endpoint를 제안하십시오.
- **[MUST] Data in Transit (TLS):** 클라우드 내부 통신이라 하더라도 모든 네트워크 통신에 TLS 암호화를 반드시 적용하도록 설계하십시오.

### 보안 그룹(SG) 인바운드 통제 예시 (Few-Shot Examples)
<examples>
<example>
[Good]
- "DB 보안 그룹의 3306 포트 인바운드를 애플리케이션 보안 그룹 ID(`sg-xxxx`)로만 제한하십시오."
- "SSH 접근을 위한 22번 포트 인바운드 소스를 사내 VPN 대역(`10.10.0.0/16`)으로만 한정하십시오."
</example>
<example>
[Bad]
- "DB 보안 그룹 3306 포트를 `0.0.0.0/0`으로 엽니다."
- "테스트를 위해 SSH 포트를 `0.0.0.0/0` 개방합니다."
</example>
</examples>

- **[Trigger: Network Rule Modified] 자가 비판 (Self-Critique):** 보안 그룹이나 네트워크 ACL 규칙 설계를 제안/수정한 직후, 스스로 `<self_critique>` 태그를 열어 **웹 포트(80/443)가 아닌 다른 포트에 대해 0.0.0.0/0 완전 개방이 존재하는지** 집중 비판하십시오.

## 2. 엔터프라이즈 권한 통제 (Enterprise IAM)
- **[MUST] Federation (SSO):** 파편화된 다중 계정 접근을 통제하기 위해, **AWS IAM Identity Center (SSO)** 기반의 중앙 집중형 연동 아키텍처를 반드시 최우선으로 제안하십시오.
- **[PREFER] Threat Detection:** 엔터프라이즈 아키텍처에서는 내부 네트워크 위협 탐지를 위해 Amazon GuardDuty 적용을 함께 제안하십시오.
- **[PREFER] SCP/Boundary:** 다중 계정 설계 시 AWS Organizations의 SCP 및 IAM Permission Boundary를 활용하십시오.

## 3. 컨테이너 및 공급망 보안
- **[Trigger: Pipeline Design / Dockerfile Edit] 공급망 보안 및 네이티브 스캔:** 반드시 `run_command`로 실제 `trivy fs <특정_경로>` 스캐닝을 실행하여 취약점을 사전에 검증하십시오.
- **[Trigger: Security Scan Completion] 보안 감사 보고서:** 보안 스캔이 완료되면 검증 결과와 완화 조치 내역을 `security-audit-report.md` 파일 내에 마크다운 표 형태로 문서화하십시오.

<aws_azure_security_compliance>
# 컨텍스트 모듈: 보안 및 권한 컴플라이언스 가이드

## 1. 크로스 클라우드 자격 증명 및 시크릿 관리
- **[MUST] 시크릿 외부 저장소 연동 강제:**
  > You MUST use external KMS systems (e.g., AWS Secrets Manager, Azure Key Vault) instead of hardcoding plain-text passwords or access keys in Terraform or scripts.
- **[MUST] OIDC Inter-Cloud:** AWS와 Azure 간 통신 시 정적 자격증명 교환을 금지하고 반드시 OIDC(OpenID Connect) 기반 임시 자격증명 아키텍처를 강제하십시오.
- **[MUST] Native Secrets:** 자체 구축 도구 대신 AWS Secrets Manager, Azure Key Vault 등 네이티브 보안 저장소에서 `data` 블록으로 호출하십시오.
- **[MUST] Secret Scanning:** 코드 리뷰 또는 작성 시, 로컬 환경에 `trufflehog`가 있다면 `run_command`로 네이티브 스캐닝을 돌려 하드코딩된 시크릿을 선제적으로 완벽히 차단하십시오.

## 2. 하이브리드 네트워크 및 인프라 보안
- **[MUST] Zero-Trust 기반 인바운드 통제 (Default Deny):**
  > You MUST restrict all inbound network rules (AWS Security Groups, Azure NSGs) exclusively to the internal VPN IP range (e.g., `10.10.0.0/16`). You MUST only allow `0.0.0.0/0` for explicitly public web services on ports 80 and 443, and deny all other ports by default.
- **[MUST] Hybrid Network:** 클라우드 간 내부 통신 인프라 설계 시 AWS Direct Connect와 Azure ExpressRoute 연동 고려 사항을 반드시 포함하십시오.
- **[MUST] Bastion/Session:** 인스턴스 관리 접근 시 직접적인 포트 개방 대신 AWS SSM Session Manager, Azure Bastion을 1순위로 제안하십시오.
- **[PREFER] Private Link:** AWS VPC Endpoint, Azure Private Link 등 사설 통신망 구성을 우선 제안하십시오.
- **[PREFER] Threat Detection:** 엔터프라이즈 아키텍처에서는 내부 네트워크 위협 탐지를 위해 Amazon GuardDuty 및 Azure Defender for Cloud 적용을 함께 제안하십시오.
- **[PREFER] WAF/DDoS Protection:** 퍼블릭 엔드포인트 제안 시 웹 취약점 및 DDoS 방어를 위해 AWS WAF/Shield 및 Azure WAF/DDoS Protection을 포함하십시오.

## 3. 통합 인증 및 최소 권한 원칙
- **[MUST] 명시적 최소 권한 부여 (PoLP 강제):**
  > You MUST adhere to the Principle of Least Privilege by explicitly defining exact AWS IAM Actions/Resources or Azure Role Definitions, avoiding the use of `*` (Wildcard).
- **[MUST] Least Privilege (Scope):** 정책 작성 시 명확한 클라우드 리소스 레벨(AWS ARN 또는 Azure Scope)을 지정하여 최소 권한의 원칙을 달성하십시오.
- **[MUST] Federation:** 다중 계정 접근을 위해 파편화된 IAM 계정을 막고 Microsoft Entra ID와 AWS IAM Identity Center 연동 SSO를 제안하십시오.

## 4. 멀티 클라우드 제로 트러스트 (Zero Trust) 아키텍처
- **[MUST] Assume Breach & SG Validation:** 모든 네트워크 트래픽은 침해되었다고 가정(Assume Breach)하십시오. 멀티 클라우드 간 통신, 인스턴스 간 통신 시 NSG(Network Security Group) 및 Security Group을 최소 권한으로 구성한 뒤, `run_command`로 `checkov -d .` 등을 실행해 허용 포트(예: 0.0.0.0/0 개방)가 없는지 물리적으로 검증하십시오.
- **[MUST] Data in Transit:** 멀티 클라우드 환경의 통신 시나리오에서는 공용 인터넷 구간 통과 가능성이 높으므로, 반드시 엔드투엔드(E2E) TLS 암호화 적용을 강제하십시오.

## 5. 파이프라인 (CI/CD) 및 공급망 보안
- **[MUST] 파이프라인 단기 자격 증명 사용 강제:**
  > You MUST enforce OIDC (OpenID Connect) for short-lived credentials when setting up GitHub Actions or CI/CD pipelines, rather than storing static AWS IAM User keys or Azure Service Principal secrets.
- **[MUST] OIDC:** 파이프라인 인증 시 반드시 OIDC(OpenID Connect) 기반의 단기 자격 증명 획득 아키텍처를 강제하십시오.
- **[MUST] Supply Chain Security & Native Scan:** 파이프라인 설계 시 컨테이너 스캐닝을 필수화하고, 로컬 터미널에 `trivy`가 설치되어 있다면 **단순 제안을 넘어 `run_command`로 실제 `trivy fs` 스캐닝을 돌려 취약점을 1차 사전 검증**하십시오.
- **[Trigger: Security Scan Completion] Security Audit Report (보안 감사 보고서):**
  > After completing a scan, DO NOT just output the results to the chat window. You MUST summarize the vulnerability list and mitigations in a table format within the `security-audit-report.md` file.
</aws_azure_security_compliance>

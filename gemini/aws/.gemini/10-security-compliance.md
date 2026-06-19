<aws_security_compliance>
# 컨텍스트 모듈: 보안 및 권한 컴플라이언스 가이드

## 1. 자격 증명 (Secrets) 관리
- **[NEVER] 시크릿 자격 증명 하드코딩 금지:**
  > NEVER hardcode plain-text AWS Access/Secret Keys or passwords into `.tf` files or playbooks.
- **[MUST] Secrets Injection:** 자격 증명은 타사 도구 대신 AWS Secrets Manager 또는 SSM Parameter Store에서 `data` 블록으로 호출하십시오.
- **[MUST] Sensitive Output:** Terraform Output 중 민감 정보는 `sensitive = true`를 선언하십시오.
- **[Trigger: Before Code Review / Commit] 시크릿 스캐닝 (Secret Scanning):**
  > When writing or reviewing code, if `trufflehog` is available locally, do not rely on mental simulation. Run native scanning using `run_command` to proactively and completely block hardcoded secrets.

## 2. 네트워크 및 엣지 보안(Edge Security)
- **[NEVER] 퍼블릭 포트 전면 개방 금지:**
  > Strictly prohibit opening port `0.0.0.0/0` (e.g., SSH 22, RDP 3389, DB ports).
- **[PREFER] WAF/Shield:** 퍼블릭 엔드포인트(ALB, CloudFront) 제안 시 AWS WAF와 Shield Advanced를 포함하십시오.
- **[MUST] Session Manager:** 인스턴스 관리 접근 시 SSH 직접 개방 대신 AWS SSM Session Manager를 1순위로 제안하십시오.
- **[MUST] VPC Endpoint:** AWS 내부 서비스(S3, DynamoDB 등) 통신 시 NAT 요금 방어를 위해 VPC Endpoint를 제안하십시오.

## 3. 엔터프라이즈 권한 통제 (IAM)
- **[NEVER] 정책 내 와일드카드 금지:**
  > NEVER use `Action: "*"` or `Resource: "*"` when writing IAM Policies.
- **[MUST] Least Privilege (ARN):** 권한 부여 시 특정 S3 버킷이나 DynamoDB 테이블 등 명확한 리소스 ARN을 지정하여 최소 권한의 원칙을 달성하십시오.
- **[MUST] Federation (SSO):** 파편화된 다중 계정 접근을 막기 위해, 단순 IAM User 생성을 지양하고 **AWS IAM Identity Center (SSO)** 기반의 중앙 집중형 연동 아키텍처를 우선 제안하십시오.
- **[PREFER] Threat Detection:** 엔터프라이즈 아키텍처에서는 내부 네트워크 위협 탐지를 위해 Amazon GuardDuty 적용을 함께 제안하십시오.
- **[PREFER] SCP/Boundary:** 다중 계정 설계 시 AWS Organizations의 SCP 및 IAM Permission Boundary를 활용하십시오.

## 4. 제로 트러스트 (Zero Trust) 아키텍처
- **[MUST] Assume Breach & SG Validation:** 모든 네트워크 트래픽은 이미 침해되었다고 가정(Assume Breach)하고 설계하십시오. VPC 및 인스턴스 간 통신 시 보안 그룹(SG)의 인바운드/아웃바운드를 최소 권한으로 구성한 뒤, `run_command`로 `checkov -d .`를 실행해 허용 포트(예: 0.0.0.0/0 개방)가 없는지 즉각 검증하십시오.
- **[MUST] Data in Transit:** 클라우드 내부 통신이라 하더라도 HTTP 사용을 지양하고 모든 통신에 TLS 암호화 적용을 우선순위로 제안하십시오.

## 5. 파이프라인 (CI/CD) 및 공급망 보안
- **[NEVER] 파이프라인 정적 키 저장 금지:**
  > NEVER store long-term AWS Access Keys as secrets in CI/CD pipelines (e.g., GitHub Actions).
- **[MUST] OIDC:** 파이프라인 인증 시 반드시 OIDC(OpenID Connect) 기반의 단기 자격 증명 획득 아키텍처를 강제하십시오.
- **[Trigger: Pipeline Design / Dockerfile Edit] 공급망 보안 및 네이티브 스캔 (Supply Chain Security & Native Scan):**
  > Mandate container scanning when designing pipelines. If `trivy` is installed locally, go beyond simple suggestions and use `run_command` to execute actual `trivy fs` scanning to proactively verify vulnerabilities.
- **[Trigger: Security Scan Completion] 보안 감사 보고서 (Security Audit Report):**
  > Once infrastructure vulnerability or container scanning is complete, you MUST document the scan results and mitigations in a Markdown table format in the dedicated `security-audit-report.md` artifact path.
</aws_security_compliance>

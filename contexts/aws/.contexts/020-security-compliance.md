<security_compliance role="Senior Cloud Architect" priority="high">
# 컨텍스트 모듈: 보안 및 권한 컴플라이언스 가이드

## 1. 자격 증명 (Secrets) 관리
- **[MUST] 시크릿 자격 증명 외부 저장소 연동 강제:** AWS Access/Secret Key나 패스워드 등 민감한 자격 증명은 반드시 `data` 블록을 사용하여 외부 시크릿 관리 서비스(AWS Secrets Manager, SSM Parameter Store 등)에서 동적으로 로드하십시오.
- **[MUST] Sensitive Output:** Terraform Output 중 민감 정보는 `sensitive = true`를 선언하십시오.
- **[MUST] Pipeline OIDC:** CI/CD 파이프라인 구성 시 반드시 OIDC를 통한 단기 자격 증명(Short-lived credentials)을 사용하십시오.
- **[Trigger: Before Code Review / Commit] 시크릿 스캐닝:** 코드를 작성하거나 리뷰할 때 반드시 `run_command`로 `trufflehog filesystem <특정_경로>` 스캐닝을 실행하여 하드코딩된 시크릿을 사전에 차단하십시오. 만약 로컬에 도구가 설치되어 있지 않다면 절대 임의로 건너뛰지 말고 즉시 작업을 중단(Halt & Clarify)한 뒤 사용자에게 설치를 요구하십시오.

## 2. 네트워크 및 엣지 보안(Edge Security)
- **[MUST] Zero-Trust 기반 인바운드 통제 (Default Deny):** 대국민 서비스용 Public ALB나 CloudFront의 웹 포트(80, 443) 외 기타 **모든 포트**(SSH, DB, Redis, 내부 API 등)의 Inbound 규칙은 반드시 사내 VPN IP 대역(예: `10.10.0.0/16`)으로만 한정하여 구성하십시오.
- **[MUST] IaC 레벨의 CIDR 유효성 검증 강제 (Code Validation):** Terraform 등에서 Public 웹 서비스(80/443) 목적이 아닌 모든 리소스의 CIDR 블록을 변수로 받을 때, 만약 값이 `0.0.0.0/0`이라면 '웹 포트 외의 전체 개방 시 보안 규정 위반으로 처리됩니다'라는 에러 메시지를 출력하고 배포를 중단시키는 `validation` 블록을 반드시 포함하십시오.
- **[PREFER] WAF/Shield:** 퍼블릭 엔드포인트(ALB, CloudFront) 제안 시 AWS WAF와 Shield Advanced를 포함하십시오.
- **[MUST] Session Manager:** 인스턴스 관리 접근 시 보안을 위해 AWS SSM Session Manager를 1순위로 제안하십시오.
- **[MUST] VPC Endpoint:** AWS 내부 서비스(S3, DynamoDB 등) 통신 시 NAT 요금 방어를 위해 VPC Endpoint를 제안하십시오.

## 3. 엔터프라이즈 권한 통제 (IAM)
- **[MUST] 명시적 최소 권한 부여 (Least Privilege):** IAM 정책 작성 시, 반드시 정확한 작업(Action) 이름과 명시적인 리소스 ARN(예: 특정 S3 버킷, DynamoDB 테이블)을 지정하여 최소 권한을 부여하십시오.
- **[MUST] Federation (SSO):** 파편화된 다중 계정 접근을 통제하기 위해, **AWS IAM Identity Center (SSO)** 기반의 중앙 집중형 연동 아키텍처를 반드시 최우선으로 제안하십시오.
- **[PREFER] Threat Detection:** 엔터프라이즈 아키텍처에서는 내부 네트워크 위협 탐지를 위해 Amazon GuardDuty 적용을 함께 제안하십시오.
- **[PREFER] SCP/Boundary:** 다중 계정 설계 시 AWS Organizations의 SCP 및 IAM Permission Boundary를 활용하십시오.

## 4. 제로 트러스트 (Zero Trust) 아키텍처
- **[MUST] Assume Breach & SG Validation:** 모든 네트워크 트래픽은 이미 침해되었다고 가정(Assume Breach)하고 설계하십시오. VPC 및 인스턴스 간 통신 시 보안 그룹(SG)의 인바운드/아웃바운드를 최소 권한으로 구성한 뒤, `run_command`로 `checkov -f <특정_파일>`을 실행해 포트 0.0.0.0/0 개방 등 과도한 허용 정책을 탐지하여 최소 권한 정책으로 즉각 수정하십시오.
- **[MUST] Data in Transit:** 클라우드 내부 통신이라 하더라도 모든 통신에 TLS 암호화를 반드시 적용하도록 설계하십시오.

## 5. 컨테이너 및 공급망 보안
- **[Trigger: Pipeline Design / Dockerfile Edit] 공급망 보안 및 네이티브 스캔:** 반드시 `run_command`로 실제 `trivy fs <특정_경로>` 스캐닝을 실행하여 취약점을 사전에 검증하십시오. 만약 로컬에 도구가 설치되어 있지 않다면 절대 임의로 건너뛰지 말고 즉시 작업을 중단(Halt & Clarify)한 뒤 사용자에게 설치를 요구하십시오.
- **[Trigger: Security Scan Completion] 보안 감사 보고서:** 보안 스캔이 완료되면 검증 결과와 완화 조치 내역을 `security-audit-report.md` 파일 내에 마크다운 표 형태로 문서화하십시오.
</security_compliance>

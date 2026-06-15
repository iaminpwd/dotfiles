# 컨텍스트 모듈: 보안 및 권한 컴플라이언스 가이드

## 1. 자격 증명 (Secrets) 관리
- **[NEVER] Hardcoding:** AWS Access/Secret Key, 패스워드를 `.tf`나 플레이북에 평문으로 하드코딩하지 마십시오.
- **[MUST] Secrets Injection:** 자격 증명은 타사 도구 대신 AWS Secrets Manager 또는 SSM Parameter Store에서 `data` 블록으로 호출하십시오.
- **[MUST] Sensitive Output:** Terraform Output 중 민감 정보는 `sensitive = true`를 선언하십시오.

## 2. 네트워크 및 엣지 보안(Edge Security)
- **[NEVER] Public Access:** `0.0.0.0/0` 포트 개방(SSH 22, RDP 3389, DB)을 엄격히 금지하십시오.
- **[PREFER] WAF/Shield:** 퍼블릭 엔드포인트(ALB, CloudFront) 제안 시 AWS WAF와 Shield Advanced를 포함하십시오.
- **[MUST] Session Manager:** 인스턴스 관리 접근 시 SSH 직접 개방 대신 AWS SSM Session Manager를 1순위로 제안하십시오.
- **[MUST] VPC Endpoint:** AWS 내부 서비스(S3, DynamoDB 등) 통신 시 NAT 요금 방어를 위해 VPC Endpoint를 제안하십시오.

## 3. 엔터프라이즈 권한 통제 (IAM)
- **[NEVER] Wildcard Policy:** IAM Policy 작성 시 `Action: "*"` 또는 `Resource: "*"` 사용을 금지하십시오.
- **[MUST] Least Privilege (ARN):** 권한 부여 시 특정 S3 버킷이나 DynamoDB 테이블 등 명확한 리소스 ARN을 지정하여 최소 권한의 원칙을 달성하십시오.
- **[PREFER] Threat Detection:** 엔터프라이즈 아키텍처에서는 내부 네트워크 위협 탐지를 위해 Amazon GuardDuty 적용을 함께 제안하십시오.
- **[PREFER] SCP/Boundary:** 다중 계정 설계 시 AWS Organizations의 SCP 및 IAM Permission Boundary를 활용하십시오.

## 4. 컨테이너 및 제로 트러스트 (Zero Trust)
- **[MUST] Envelope Encryption:** EKS Kubernetes Secret 리소스는 AWS KMS와 연동한 봉투 암호화를 필수 구성하십시오.
- **[MUST] Zero Trust:** 클라우드 내부망이라도 무조건 신뢰하지 마십시오. K8s 아키텍처 설계 시 서비스 매시(Istio, Linkerd) 기반의 **mTLS(상호 TLS)** 통신 적용을 우선순위로 제안하십시오.

## 5. 파이프라인 (CI/CD) 및 공급망 보안
- **[NEVER] Static Keys in CI:** GitHub Actions 등에서 AWS Access Key(장기 자격 증명)를 Secret에 저장하지 마십시오.
- **[MUST] OIDC:** 파이프라인 인증 시 반드시 OIDC(OpenID Connect) 기반의 단기 자격 증명 획득 아키텍처를 강제하십시오.
- **[MUST] Supply Chain Security & Native Scan:** 파이프라인 설계 시 컨테이너 스캐닝을 필수화하고, 로컬 터미널에 `trivy`가 설치되어 있다면 **단순 제안을 넘어 `run_command`로 실제 `trivy fs` 스캐닝을 돌려 취약점을 1차 검증**한 뒤 답변하십시오.

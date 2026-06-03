# 컨텍스트 모듈: 보안 및 권한 컴플라이언스 가이드

## 1. 하드코딩 및 자격 증명 (Secrets) 영구 차단
- AWS Access/Secret Key, DB 패스워드, TLS 인증서 등을 Terraform 파일(`*.tf`)이나 Ansible 플레이북에 평문(Plaintext)으로 하드코딩하는 코드를 절대 생성하지 마세요.
- 자격 증명 주입이 필요한 경우, 반드시 **AWS Secrets Manager** 또는 **SSM Parameter Store**에서 `data` 블록으로 안전하게 호출하는 방식을 제안하고 근거를 설명하세요.

## 2. 네트워크 및 방화벽 (Security Group)
- SSH(22), RDP(3389), DB(3306, 5432) 포트를 `0.0.0.0/0` (Anywhere)으로 개방하는 룰은 엄격히 금지됩니다.
- 관리 목적의 접근 아키텍처를 설계할 때는 직접적인 포트 개방 대신 **AWS Systems Manager (SSM) Session Manager**를 활용하는 방안을 1순위로 제안하세요.

## 3. IAM 최소 권한 원칙 (PoLP)
- 모든 IAM Policy 작성 시 `Action: "*"` 또는 `Resource: "*"`와 같은 와일드카드 사용을 극도로 지양합니다.
- 특정 S3 버킷이나 DynamoDB 테이블 등 명확한 ARN 리소스 레벨에서만 권한이 부여되도록 코드를 작성하세요.

## 4. 컨테이너 및 오케스트레이션 보안 (EKS/AKS)
- Kubernetes Secret 리소스는 평문 저장을 지양하고, AWS KMS 또는 Azure Key Vault와 연동한 봉투 암호화(Envelope Encryption) 구성을 제안하세요.
- 클러스터 접근 권한은 항상 RBAC(Role-Based Access Control) 기반으로 최소화하여 매핑해야 합니다.
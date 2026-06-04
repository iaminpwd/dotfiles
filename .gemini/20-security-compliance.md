# 컨텍스트 모듈: Cloud Native 및 Day-2 운영 표준

## 1. 선언적 배포 및 버전 고정 (GitOps)
- Kubernetes 워크로드 배포 관련 질문 시, 수동 개입을 지양하고 자동화와 상태 관리가 용이한 **GitOps(예: ArgoCD)** 기반의 아키텍처를 우선순위에 둡니다.
- CI(빌드/테스트/이미지 푸시)와 CD(매니페스트 동기화 및 배포) 파이프라인의 역할을 엄격히 분리하여 설계하세요.
- 코드 작성 시 반드시 최신 안정 버전(Stable)을 사용하되, 실무 환경의 안정성을 위해 컨테이너 이미지(`latest` 태그 금지), Helm 차트, Terraform 모듈의 **명시적인 버전 고정(Version Pinning)**을 적용하세요.

## 2. 가시성 (Observability) 및 유지보수
- 리소스 생성 가이드를 제공할 때, 구축 이후의 운영 단계에서 반드시 고려해야 할 모니터링(**Prometheus/Grafana** 등), 중앙 집중식 로깅, 트레이싱 등 유지보수 관점의 조언을 함께 제공하세요.

## 3. FinOps 및 비용 최적화
- 아키텍처나 인프라 구성 제안 시, 오버프로비저닝을 방지하고 비용 효율성을 극대화할 수 있는 방안(예: Spot Instance 활용, ARM/Graviton 프로세서 전환, Auto Scaling 최적화 등)을 함께 고려하여 제안하세요.

## 4. 재해 복구(DR) 및 롤백(Rollback) 전략
- 글로벌 멀티 리전 아키텍처 제안 시 비즈니스 연속성 요구사항(RTO/RPO)을 고려하여 **Pilot Light** 또는 **Warm Standby**와 같은 구체적인 재해 복구 모델을 기반으로 설계하세요.
- 애플리케이션 및 인프라 배포 실패 상황을 대비하여 GitOps 기반의 자동/수동 롤백 파이프라인과 안전한 트래픽 전환(Blue/Green, Canary) 전략을 아키텍처에 반드시 포함하세요.


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
# 컨텍스트 모듈: Cloud Native 및 Day-2 운영 표준

## 1. 선언적 배포 및 버전 고정 (GitOps)
- Kubernetes 워크로드 배포 관련 질문 시, 수동 개입을 엄격히 금지하고 자동화와 상태 관리가 용이한 **GitOps(예: ArgoCD)** 기반의 아키텍처를 우선적으로 설계하세요.
- CI(빌드/테스트/이미지 푸시)와 CD(매니페스트 동기화 및 배포) 파이프라인의 역할을 엄격히 분리하여 설계하세요.
- 실무 환경의 안정성을 위해 컨테이너 이미지(`latest` 태그 금지), Helm 차트, Terraform 모듈의 **명시적인 버전 고정(Version Pinning)**을 반드시 적용하세요.

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
- 자격 증명 주입이 필요한 경우, 타사 도구 제안을 금지하고 반드시 **AWS Secrets Manager** 또는 **AWS Systems Manager (SSM) Parameter Store**에서 `data` 블록으로 안전하게 호출하는 방식을 제안하세요.
- Terraform 작성 시 패스워드나 인증 키 같은 민감 정보가 Output으로 출력되어야 할 경우, CI/CD 파이프라인 로그 유출을 막기 위해 반드시 `sensitive = true` 속성을 명시하세요.

## 2. 네트워크 및 엣지 보안(Edge Security)
- SSH(22), RDP(3389), DB(3306, 5432) 포트를 `0.0.0.0/0` (Anywhere)으로 개방하는 룰 작성은 엄격히 금지하세요.
- 퍼블릭 대상의 아키텍처(예: ALB, CloudFront) 설계 시, L7 방어망 강화를 위해 반드시 **AWS WAF**와 **AWS Shield Advanced** 적용을 기본 아키텍처로 포함하세요. 내부 네트워크에는 **Amazon GuardDuty**를 활용한 위협 탐지 구성을 제안하세요.
- 관리 목적의 접근 아키텍처를 설계할 때는 직접적인 포트 개방 대신 무조건 **AWS Systems Manager (SSM) Session Manager**를 활용하는 방안을 1순위로 제안하세요.
- S3, DynamoDB 등 AWS 내부 서비스와 통신하는 아키텍처 설계 시, NAT Gateway로 인한 데이터 전송 요금을 방어하고 내부 보안을 강화하기 위해 **AWS VPC Endpoint (Gateway/Interface)** 구성을 우선적으로 제안하세요.

## 3. 엔터프라이즈 권한 통제 (IAM & SCP)
- 모든 IAM Policy 작성 시 `Action: "*"` 또는 `Resource: "*"`와 같은 와일드카드 사용을 엄격히 금지하세요.
- 특정 S3 버킷이나 DynamoDB 테이블 등 명확한 ARN 리소스 레벨에서만 권한이 부여되도록 코드를 작성하세요.
- 대규모 조직의 거버넌스를 위해 다중 계정(Multi-Account) 설계가 필요할 경우, 개별 IAM Policy 대신 **AWS Organizations의 SCP(Service Control Policies)**와 **IAM Permission Boundary**를 활용한 중앙 집중식 권한 통제 아키텍처를 제안하세요.

## 4. 컨테이너 및 오케스트레이션 보안 (EKS/AKS)
- Amazon EKS 환경에서 Kubernetes Secret 리소스는 평문 저장을 엄격히 금지하고, 반드시 **AWS KMS**와 연동한 봉투 암호화(Envelope Encryption) 구성을 제안하세요.
- 클러스터 접근 권한은 항상 RBAC(Role-Based Access Control) 기반으로 최소화하여 매핑하세요.
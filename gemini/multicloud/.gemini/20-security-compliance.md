# 컨텍스트 모듈: Cloud Native 및 Day-2 운영 표준

## 1. 선언적 배포 및 버전 고정 (GitOps)
- Kubernetes 워크로드 배포 관련 질문 시, 수동 개입을 엄격히 금지하고 자동화와 상태 관리가 용이한 **GitOps(예: ArgoCD)** 기반의 아키텍처를 우선적으로 설계하세요.
- CI(빌드/테스트/이미지 푸시)와 CD(매니페스트 동기화 및 배포) 파이프라인의 역할을 엄격히 분리하여 설계하세요.
- 실무 환경의 안정성을 위해 컨테이너 이미지(`latest` 태그 금지), Helm 차트, Terraform 모듈의 **명시적인 버전 고정(Version Pinning)**을 반드시 적용하세요.

## 2. 가시성 (Observability) 및 유지보수
- 리소스 생성 가이드를 제공할 때, 구축 이후의 운영 단계에서 반드시 고려해야 할 모니터링(**Prometheus/Grafana** 등), 중앙 집중식 로깅, 트레이싱 등 유지보수 관점의 조언을 함께 제공하세요.

## 3. FinOps 및 비용 최적화
- 아키텍처나 인프라 구성 제안 시, 오버프로비저닝을 방지하고 비용 효율성을 극대화할 수 있는 방안(예: Spot Instance/VM 활용, ARM 프로세서 전환, Auto Scaling 최적화 등)을 함께 고려하여 제안하세요.

## 4. 재해 복구(DR) 및 롤백(Rollback) 전략
- 글로벌 멀티 리전 아키텍처 제안 시 비즈니스 연속성 요구사항(RTO/RPO)을 고려하여 **Pilot Light** 또는 **Warm Standby**와 같은 구체적인 재해 복구 모델을 기반으로 설계하세요.
- 애플리케이션 및 인프라 배포 실패 상황을 대비하여 GitOps 기반의 자동/수동 롤백 파이프라인과 안전한 트래픽 전환(Blue/Green, Canary) 전략을 아키텍처에 반드시 포함하세요.


# 컨텍스트 모듈: 보안 및 권한 컴플라이언스 가이드

## 1. 크로스 클라우드 자격 증명 및 하드코딩 영구 차단
- 클라우드 자격 증명(AWS Access Key, Azure Service Principal 등), DB 패스워드, TLS 인증서 등을 Terraform 파일(`*.tf`)이나 Ansible 플레이북에 평문(Plaintext)으로 하드코딩하는 코드를 절대 생성하지 마세요.
- **이기종 클라우드 간 통신 보안:** AWS 리소스가 Azure API를 호출하거나 반대 상황일 경우, 정적 자격증명(Access Key/Secret) 교환을 엄격히 금지하고 반드시 **OIDC (OpenID Connect)** 기반의 임시 자격증명 획득 아키텍처를 강제 제안하세요.
- 자격 증명 주입이 필요한 경우, 자체 구축 도구 제안을 금지하고 반드시 클라우드 네이티브 보안 저장소(예: **AWS Secrets Manager**, **Azure Key Vault**)에서 `data` 블록으로 안전하게 호출하는 방식을 제안하세요.
- Terraform 작성 시 패스워드나 인증 키 같은 민감 정보가 Output으로 출력되어야 할 경우, CI/CD 파이프라인 로그 유출을 막기 위해 반드시 `sensitive = true` 속성을 명시하세요.

## 2. 하이브리드 네트워크 및 엣지 보안
- SSH(22), RDP(3389), DB(3306, 5432) 포트를 `0.0.0.0/0` (Anywhere)으로 개방하는 룰 작성은 엄격히 금지하세요.
- **멀티 클라우드 전용선 매핑:** 클라우드 간 내부 통신 인프라 설계 시, **AWS Direct Connect**와 **Azure ExpressRoute**를 연동하는 엔터프라이즈 하이브리드 네트워킹 고려 사항을 반드시 포함하세요.
- 관리 목적의 인스턴스 접근 아키텍처를 설계할 때는 직접적인 SSH/RDP 포트 개방 대신 클라우드 보안 접근 서비스(예: **AWS SSM Session Manager**, **Azure Bastion**)를 활용하는 방안을 1순위로 제안하세요.
- S3, Blob Storage 등 클라우드 내부 서비스와 통신하는 아키텍처 설계 시, NAT 전송 요금을 방어하고 내부 보안을 강화하기 위해 사설 통신망(예: **AWS VPC Endpoint**, **Azure Private Link**) 구성을 우선적으로 제안하세요.

## 3. 통합 인증 및 최소 권한 원칙 (IAM/RBAC)
- 모든 클라우드 Policy 작성 시 와일드카드(`Action: "*"` 또는 `Resource: "*"`) 사용을 엄격히 금지하세요.
- 특정 S3 버킷/DynamoDB 테이블(AWS)이나 Storage Account(Azure) 등 명확한 리소스(ARN/Scope) 레벨에서만 권한이 부여되도록 코드를 작성하세요.
- 이기종 클라우드의 다중 계정 접근을 위해, 파편화된 IAM 계정 발급을 막고 **Microsoft Entra ID (구 Azure AD)**와 **AWS IAM Identity Center**를 연동한 SSO(Single Sign-On) 페더레이션 구성을 최우선으로 제안하세요.

## 4. 컨테이너 및 오케스트레이션 보안 (EKS/AKS)
- EKS/AKS 환경에서 Kubernetes Secret 리소스는 평문 저장을 엄격히 금지하고, 반드시 클라우드 네이티브 키 관리(예: **AWS KMS**, **Azure Key Vault**)와 연동한 봉투 암호화(Envelope Encryption) 구성을 제안하세요.
- 클러스터 접근 권한은 항상 RBAC(Role-Based Access Control) 기반으로 최소화하여 매핑하세요.
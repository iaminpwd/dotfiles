# 컨텍스트 모듈: IaC (Terraform & Ansible) 엔지니어링 표준

## 1. 공통 원칙 (Provisioning & Configuration)
- **역할 분리 (Decoupling):** Terraform은 인프라 리소스(VPC, EC2, EKS 등)의 수명 주기를 관리하고, Ansible은 배포된 리소스 내부의 OS 설정 및 애플리케이션 구성을 담당합니다. 
- Terraform 내장 프로비저너(`local-exec`, `remote-exec`) 사용은 멱등성을 훼손하므로 엄격히 금지하며, OS 구성은 완전히 Ansible로 이관합니다.

## 2. Terraform 엔지니어링 표준
- **버전:** Terraform v1.5.x 이상, AWS Provider v5.x 이상 기준.
- **다중 리전 및 확장성:** 글로벌 멀티 리전 DR 확장을 위해 Provider 블록에 `alias`를 사용하고, 가용 영역(AZ)은 하드코딩 대신 `data "aws_availability_zones"`로 동적 매핑합니다.
- **State 격리 및 보존:** 로컬 State 저장을 금지하며, **AWS S3 Backend**와 **DynamoDB State Locking**을 필수 구성합니다. 네트워크, DB, App 계층의 State는 단일 `main.tf`에 종속되지 않도록 디렉터리 단위로 격리합니다.

## 3. Ansible 엔지니어링 표준
- **멱등성(Idempotency) 보장:** `shell`이나 `command` 모듈 사용을 최후의 수단으로 제한하고, 반드시 OS 및 애플리케이션 제어를 위한 **전용 모듈(예: `yum`, `systemd`, `template`, `file`)**을 우선 사용합니다.
- **동적 인벤토리 (Dynamic Inventory):** 클라우드 환경의 유동적인 IP를 고려하여 정적 인벤토리 파일(하드코딩) 사용을 지양하고, **AWS EC2 Dynamic Inventory Plugin**(`aws_ec2.yml`)을 활용해 EC2 태그(Tag) 기반으로 타겟 노드를 동적 그룹화합니다.
- **변수 암호화:** 민감한 변수(DB 패스워드, 인증 키 등)는 평문으로 노출하지 않고 **Ansible Vault**를 사용하여 암호화 처리 구조를 제안합니다.
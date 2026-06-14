# 컨텍스트 모듈: IaC (Terraform & Ansible) 엔지니어링 표준

## 1. 공통 원칙 (Provisioning & Configuration)
- **역할 분리 (Decoupling):** Terraform은 인프라 리소스(VPC/VNet, EC2/VM, EKS/AKS 등)의 수명 주기를 관리하고, Ansible은 배포된 리소스 내부의 OS 설정 및 애플리케이션 구성을 담당하도록 설계하세요. 
- Terraform 내장 프로비저너(`local-exec`, `remote-exec`) 사용은 멱등성을 훼손하므로 엄격히 금지하며, OS 구성은 완전히 Ansible로 이관하세요.

## 2. Terraform 엔지니어링 표준
- **다중 리전 및 확장성:** 글로벌 멀티 리전 DR 확장을 위해 Provider 블록에 `alias`를 사용하고, 가용 영역(AZ)은 하드코딩 대신 Data Source(예: `data "aws_availability_zones"`, `data "azurerm_availability_zones"`)로 동적 매핑하세요.
- **멀티 클라우드 프로바이더 관리:** 하나의 리포지토리에서 멀티 클라우드를 구성할 경우, `providers.tf`에 AWS와 Azure의 인증 방식과 버전을 명확히 분리 선언하여 프로바이더 간 충돌을 방지하세요.
- **멀티 클라우드 중앙 집중형 State 아키텍처:** 클라우드별로 State가 파편화(S3, Blob 등)되는 것을 방지하기 위해, 멀티 클라우드 인프라 설계 시 **Terraform Cloud (HCP)** 또는 **GitLab CI**의 관리형 State Backend를 활용하여 중앙 집중적으로 Locking과 State를 통제하는 방안을 강력히 제안하세요.
- **State 격리 및 보존:** 로컬 State 저장을 금지하며, 네트워크, DB, App 계층의 State는 단일 `main.tf`에 종속되지 않도록 디렉터리 단위로 엄격히 격리하세요.
- **전사적 리소스 태깅(Tagging):** FinOps 및 리소스 추적을 위해 Terraform으로 생성하는 모든 인프라 리소스에 `Environment`, `Owner`, `Project` 등의 표준 `tags` 블록을 필수로 포함하세요.
- **다중 환경(Multi-Env) 아키텍처:** 단일 환경용 하드코딩을 엄격히 금지하고, Dev/Stg/Prod 다중 환경 확장을 전제로 `tfvars` 또는 `Workspace` 기반의 변수 주입(Variable Injection) 아키텍처를 적용하세요.
- **Stateful 리소스 보호:** 데이터베이스(RDS/Azure SQL), 스토리지(S3/Blob) 등 데이터 유실 위험이 있는 리소스의 코드 제안 시, 반드시 `lifecycle { prevent_destroy = true }` 블록이나 스냅샷 백업 속성을 포함하세요.

## 3. Ansible 엔지니어링 표준
- **멱등성(Idempotency) 보장:** `shell`이나 `command` 모듈 사용을 최후의 수단으로 제한하고, 반드시 OS 및 애플리케이션 제어를 위한 **전용 모듈(예: `package`, `systemd`, `template`, `file`)**을 우선 사용하세요.
- **동적 인벤토리 (Dynamic Inventory):** 클라우드 환경의 유동적인 IP를 고려하여 정적 인벤토리 파일(하드코딩) 사용을 엄격히 금지하고, 클라우드 전용 플러그인(예: `aws_ec2.yml`, `azure_rm.yml`)을 활용해 리소스 태그(Tag) 기반으로 타겟 노드를 동적 그룹화하세요.
- **변수 암호화:** 민감한 변수(DB 패스워드, 인증 키 등)는 평문으로 노출하지 않고 **Ansible Vault**를 사용하여 암호화 처리 구조를 구성하세요.
# 컨텍스트 모듈: IaC (Terraform & Ansible) 엔지니어링 표준

## 1. 공통 원칙 (Provisioning & Configuration)
- **[MUST] Decoupling:** Terraform은 인프라 리소스 수명 주기 관리, Ansible은 OS 설정 및 앱 구성 담당으로 역할을 엄격히 분리하세요.
- **[NEVER] Provisioner:** Terraform 내장 프로비저너(`local-exec`, `remote-exec`) 사용을 멱등성 훼손 사유로 엄격히 금지하세요.

## 2. Terraform 엔지니어링 표준
- **[PREFER] TGW:** 1:1 VPC Peering 복잡성을 피하고 AWS Transit Gateway(TGW) 기반의 중앙 집중형 라우팅을 제안하세요.
- **[MUST] State Management:** 로컬 State 저장을 절대 금지하며, AWS S3 Backend + DynamoDB State Locking을 필수 구성하세요.
- **[MUST] Multi-Env:** 하드코딩을 금지하고 `tfvars` 또는 Workspace 기반의 변수 주입(Variable Injection) 아키텍처를 적용하세요.
- **[MUST] Dynamic Mapping:** 글로벌 리전 확장성을 위해 리소스 가용 영역(AZ)은 하드코딩하지 말고 `data "aws_availability_zones"` 블록 등을 활용하여 동적으로 매핑하세요.
- **[MUST] Stateful Protection:** DB나 스토리지 리소스 제안 시 `prevent_destroy = true`를 반드시 포함하세요.
- **[MUST] Resource Iteration:** 다수의 리소스를 반복 생성할 때 인덱스 변경에 따른 파괴적 재생성(State Shift)을 방지하기 위해 `count` 대신 반드시 `for_each`와 `map/set`을 활용하세요.
- **[MUST] Module Composition:** 코드를 단일 파일에 모노리틱하게 작성하지 말고, 재사용 가능한 자식 모듈(Child Module)과 환경별 루트 모듈(Root Module)로 철저히 분리(Decoupling)하세요.

## 3. Ansible 엔지니어링 표준
- **[MUST] Idempotency:** `shell`이나 `command` 모듈 대신 `yum`, `systemd`, `file` 등 전용 모듈을 최우선으로 사용하세요.
- **[MUST] Dynamic Inventory:** 하드코딩된 정적 인벤토리를 금지하고, AWS EC2 Dynamic Inventory Plugin(`aws_ec2.yml`)을 활용하세요.
- **[MUST] Vault:** 민감한 변수(DB 패스워드 등)는 Ansible Vault로 암호화하세요.
- **[MUST] Native Syntax Check:** 플레이북 작성 시, 로컬에 `ansible-playbook`이 있다면 `run_command`로 `--syntax-check` 모드를 실행해 문법 오류를 스스로 검증하세요.

## 4. 엔터프라이즈 명명 규칙 및 태깅
- **[MUST] Naming & FinOps Tagging:** 모든 리소스 이름은 `<Project>-<Environment>-<Service>-<Resource>` 규칙을 따르고, `Owner`, `Environment`, `CostCenter` 3대 필수 태그가 거버넌스 레벨에서 강제된다고 가정하여 `default_tags` 등에 반드시 포함하세요.

## 5. Policy-as-Code (PaC) 및 거버넌스
- **[MUST] PaC & Native Validation:** 단순한 IaC를 넘어 Open Policy Agent(OPA) Rego 정책 구성을 강제하고, 로컬에 `conftest` 도구가 있다면 **직접 터미널 명령어를 실행하여 작성한 코드가 사내 규정(Policy)을 위반하지 않는지 사전 검증(Pre-flight)**하세요.
<aws_azure_iac_standard>
# 컨텍스트 모듈: IaC (Terraform & Ansible) 엔지니어링 표준

## 1. 공통 원칙 (Provisioning & Configuration)
- **[MUST] Decoupling:** Terraform은 인프라 리소스 수명 주기 관리, Ansible은 OS 설정 및 앱 구성 담당으로 역할을 엄격히 분리하십시오.
- **[NEVER] Provisioner (내장 프로비저너 금지):**
  > NEVER use Terraform built-in provisioners (`local-exec`, `remote-exec`) as they strictly violate idempotency.

## 2. 멀티 클라우드 Terraform 엔지니어링 표준
- **[MUST] Plan Analysis CoT (AI Rule):** `terraform plan` 결과를 리뷰할 때, 결과를 기계적으로 읽지 말고 반드시 `<thinking>` 태그 내에서 파괴적 변경(Destroy/Replace)이나 State Drift의 근본 원인을 먼저 분석하십시오.
- **[MUST] Multi-Provider:** 멀티 리전 및 멀티 클라우드 확장을 위해 Provider 블록에 `alias`를 적극 사용하고, 리전/가용 영역은 동적 데이터 소스(`data`)로 매핑하십시오.
- **[MUST] State Management:** 로컬 State 저장을 금지하며, 클라우드 스토리지(AWS S3+DynamoDB 또는 Azure Blob+State Locking)를 필수 구성하십시오.
- **[MUST] Multi-Env (Terragrunt):** 단순 `tfvars`나 Workspace 하드코딩을 지양하고, **Terragrunt**를 활용하여 환경별(Dev/Prod) 상태(State) 격리 및 변수 주입(Variable Injection) 아키텍처를 적용하십시오.
- **[MUST] Dynamic Mapping:** 글로벌 리전 확장성을 위해 리소스 가용 영역(AZ)은 하드코딩하지 말고 클라우드별 동적 데이터 소스(Data source)를 활용하여 매핑하십시오.
- **[MUST] Stateful Protection:** 데이터 유실 위험이 있는 리소스 제안 시 `prevent_destroy = true`를 반드시 포함하십시오.
- **[MUST] Resource Iteration:** 다수의 리소스를 반복 생성할 때 인덱스 변경에 따른 파괴적 재생성(State Shift)을 방지하기 위해 `count` 대신 반드시 `for_each`를 활용하십시오. 단, 리소스 ID처럼 Apply 이후에 결정되는 동적 값(`known after apply`)을 반복할 때는 `set` 대신 반드시 정적 식별자(Static Key)를 갖는 `map` 구조를 강제하여 Plan 오류를 방지하십시오.
- **[MUST] Version Pinning:** 인프라의 예측 가능성을 위해 Terraform 코어 및 Provider 버전(`required_version`, `required_providers`)은 반드시 특정 버전(또는 `~>` 구문)으로 명시하여 고정하십시오.
- **[MUST] Module Composition:** 코드를 단일 파일에 모노리틱하게 작성하지 말고, 재사용 가능한 자식 모듈(Child Module)과 환경별 루트 모듈(Root Module)로 철저히 분리(Decoupling)하십시오.
- **[MUST] Auto Documentation:** 인프라 코드 작성 및 수정 후, 로컬에 `terraform-docs` 도구가 있다면 `run_command`를 통해 README.md를 자동 생성하여 문서화를 강제하십시오.
- **[Trigger: Before Terraform Apply] Explicit Drift Check (명시적 편차 검증):**
  > Before executing destructive commands, you MUST first run `terraform plan` and analyze the results based on actual output to verify (Drift Check) if any unintended resource destruction (Destroy) or replacement (Replace) occurs.
- **[MUST] SG Lazy Deletion Prevention:** Lambda 등 VPC ENI와 강하게 결합되는 Security Group을 다룰 때는, AWS의 ENI 지연 삭제(Lazy Deletion)로 인한 Terraform 무한 대기(Deadlock)를 방지하기 위해 반드시 `name` 대신 `name_prefix = "..."`를 사용하고, `lifecycle { create_before_destroy = true }` 블록을 필수로 포함하십시오.
- **[Trigger: Terraform Apply Completion] IaC Deployment Summary (IaC 배포 요약):**
  > Immediately after a successful Terraform deployment, document the state changes (Drift list) and estimated cost impact in the `iac-deployment-summary.md` artifact file.

## 3. Ansible 엔지니어링 표준
- **[MUST] Idempotency:** `shell`이나 `command` 모듈 대신 `yum`, `apt`, `systemd`, `file` 등 전용 모듈을 최우선으로 사용하십시오.
- **[MUST] Deterministic Packages:** 패키지 설치 시 예측 불가능한 업데이트를 막기 위해 `state: latest` 사용을 금지하고, `state: present`(또는 특정 버전)를 사용하십시오.
- **[MUST] Dynamic Inventory:** 하드코딩된 정적 인벤토리를 금지하고, 클라우드 동적 인벤토리 플러그인(`aws_ec2.yml`, `azure_rm.yml`)을 활용하십시오.
- **[MUST] Vault:** 민감한 변수(DB 패스워드 등)는 Ansible Vault로 암호화하십시오.
- **[MUST] Native Syntax Check:** 플레이북 작성 시, 로컬에 `ansible-playbook`이 있다면 `run_command`로 `--syntax-check` 모드를 실행해 문법 오류를 스스로 검증하십시오.

## 4. 엔터프라이즈 명명 규칙 및 태깅
- **[MUST] Naming & FinOps Tagging:** 모든 리소스 이름은 `<Project>-<Env>-<Service>-<Resource>` 규칙을 따르고, `Project`, `Environment`, `CostCenter` 3대 필수 태그가 거버넌스 레벨에서 강제된다고 가정하여 `default_tags` 등에 반드시 포함하십시오.

## 5. Policy-as-Code (PaC) 및 거버넌스
- **[MUST] PaC & Native Validation:** 단순한 IaC를 넘어 Open Policy Agent(OPA) Rego 정책 구성을 강제하고, 로컬에 `conftest` 도구가 있다면 **직접 터미널 명령어를 실행하여 작성한 코드가 사내 규정(Policy)을 위반하지 않는지 사전 검증(Pre-flight)**하십시오.
</aws_azure_iac_standard>

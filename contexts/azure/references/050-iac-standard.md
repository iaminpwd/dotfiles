---
role: Senior Cloud Architect
priority: high
trigger: Apply these rules ONLY when writing or reviewing Terraform, Terragrunt, or Ansible code.
---
# 컨텍스트 모듈: IaC (Terraform & Ansible) 엔지니어링 표준

## 1. 공통 원칙 (Provisioning & Configuration)
- **[MUST] Decoupling:** Terraform은 인프라 리소스 수명 주기 관리, Ansible은 OS 설정 및 앱 구성 담당으로 역할을 엄격히 분리하십시오.
- **[MUST] Declarative Configuration Management (선언적 구성 관리 강제):** 멱등성(Idempotency)을 유지하기 위해 시스템 설정 시 반드시 전용 구성 관리 도구(예: Ansible)나 네이티브 OS 스크립트(`user_data`)를 사용하십시오.

## 2. Terraform 엔지니어링 표준
- **[MUST] Active Investigation (Step 0. 사전 팩트 검증):** Terraform(IaC) 코드 작성 전, 반드시 `run_command`로 `az [서비스] show/list` 명령어를 실행하여 현재 Azure 계정의 실제 리소스(VNet, Subnet, RBAC Role 등) 상태를 먼저 물리적으로 조회하고, 그 팩트만을 유일한 근거로 삼아 코드를 제안하십시오.
- **[MUST] Static Code Analysis (tflint 강제):** 코드를 검증하거나 모의 실행(Dry-Run)하기 전, 가장 먼저 `tflint --init` 및 `tflint` 명령어를 실행하여 Azure Provider 문법 및 Best Practice 위반 사항이 없는지 정적 분석을 1순위로 수행하십시오.
- **[PREFER] vWAN:** 글로벌 확장성 확보를 위해 Azure Virtual WAN(vWAN) 기반의 중앙 집중형 라우팅을 적극 제안하십시오.
- **[MUST] State Management:** State 저장은 반드시 Azure Blob Storage Backend와 자체 임대(Lease) 기반 State Locking을 사용하여 원격으로 안전하게 구성하십시오.
- **[MUST] Multi-Env (Terragrunt):** 다중 환경 관리 시 **Terragrunt**를 활용하여 환경별(Dev/Prod) 상태(State) 격리 및 변수 주입(Variable Injection) 아키텍처를 우선적으로 적용하십시오.
- **[MUST] Dynamic Mapping:** 글로벌 리전 확장성을 위해 리소스 가용 영역(AZ)은 `data "azurerm_availability_zones"` 블록 등을 활용하여 동적으로 매핑하십시오.
- **[MUST] Stateful Protection:** DB나 스토리지 리소스 제안 시 `prevent_destroy = true`를 반드시 포함하십시오.
- **[MUST] Resource Iteration:** 다수의 리소스를 반복 생성할 때 인덱스 변경에 따른 안정적인 재생성(State Shift) 제어를 위해 반드시 `for_each`를 활용하십시오. 단, 리소스 ID처럼 Apply 이후에 결정되는 동적 값(`known after apply`)을 반복할 때는 반드시 정적 식별자(Static Key)를 갖는 `map` 구조를 강제하여 안정적인 Plan 실행을 보장하십시오.
- **[MUST] Version Pinning:** 인프라의 예측 가능성을 위해 Terraform 코어 및 Azure Provider 버전(`required_version`, `required_providers`)은 반드시 특정 버전(또는 `~>` 구문)으로 명시하여 고정하십시오.
- **[MUST] Module Composition:** 코드를 재사용 가능한 자식 모듈(Child Module)과 환경별 루트 모듈(Root Module)로 철저히 분리(Decoupling)하십시오.
- **[MUST] Auto Documentation:** 인프라 코드 작성 및 수정 후, 반드시 `run_command`를 통해 `terraform-docs markdown <특정_경로>` 도구를 실행하여 README.md를 자동 생성해 문서화를 강제하십시오.

### State 관리 및 의존성 예시 (Few-Shot Examples)
<examples>
<example>
[Good]
```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stterraformstate"
    container_name       = "tfstate"
    key                  = "prod/vnet/terraform.tfstate"
  }
}
```
</example>
<example>
[Bad]
```hcl
# backend 블록 누락 (로컬 state 사용)
# storage_account_name 누락 (동시성 제어 불가)
```
</example>
</examples>

- **[Trigger: Before Terraform Apply] 자가 비판 및 구조화된 채점 (Self-Critique & Structured Judge):** 상태 변경 명령어를 실행하기 전, 반드시 `terraform plan -input=false`를 실행(입력 대기로 인한 Lock 무한 대기 방지)하고 스스로 `<self_critique>` 태그를 열어 다음 2가지 기준(Metric)으로 현재 Plan 결과를 1~5점으로 채점하십시오. (단순히 리소스 변경 목록만 빠르게 조회할 목적이라면 `terraform plan -lock=false` 사용을 적극 제안하십시오.) (채점 시 반드시 `- [기준명]: [점수]점 - 사유: ...` 포맷을 명시적으로 사용하십시오.)
  - Criteria 1 (안전성): 의도치 않은 리소스 파괴(Destroy)나 프로덕션 다운타임이 발생하는가?
  - Criteria 2 (보안성): NSG나 RBAC 권한이 과도하게 열려있지 않은가? (5점: 완벽히 안전 / 3점: 경고 수준 / 1점: 치명적 위험)
  채점 결과가 두 기준 모두 5점 만점일 경우에만 사용자에게 Plan 결과와 채점 내용을 보고하고 명시적인 `[Apply 승인]`을 요청하십시오. 5점 미만일 경우 코드를 안전하게 수정하여 재작성하십시오.
- **[MUST] NSG Lazy Deletion Control:** Azure Functions 등 VNet NIC와 강하게 결합되는 Network Security Group(NSG)을 다룰 때는, Azure의 네트워크 인터페이스(NIC) 지연 삭제 과정 등에서 안정적인 리소스 수명 주기 제어(Lifecycle Management)를 보장하기 위해 `name_prefix = "..."`를 적극 사용하고, `lifecycle { create_before_destroy = true }` 블록을 필수로 포함하십시오.
- **[Trigger: Terraform Apply Completion] IaC 배포 요약 (IaC Deployment Summary):** Terraform Apply가 성공적으로 완료된 직후, 추가/변경/삭제된 리소스 목록(Drift)과 `infracost`를 통한 예상 비용 영향을 `iac-deployment-summary.md` 산출물에 문서화하십시오.

## 3. Ansible 엔지니어링 표준
- **[MUST] Idempotency:** `yum`, `systemd`, `file` 등 전용 모듈을 최우선으로 사용하여 멱등성을 달성하십시오.
- **[MUST] Deterministic Packages:** 패키지 설치 시 예측 가능한 멱등성(Idempotency)을 보장하기 위해 반드시 `state: present`(또는 특정 버전)를 명시적으로 지정하여 사용하십시오.
- **[MUST] Dynamic Inventory:** 인벤토리 구성 시 반드시 Azure VM Dynamic Inventory Plugin(`azure_rm.yml`) 기반의 동적 인벤토리(Dynamic Inventory)를 활용하십시오.
- **[MUST] Vault:** 민감한 변수(DB 패스워드 등)는 Ansible Vault로 암호화하십시오.
- **[MUST] Native Syntax Check:** 플레이북 작성 시 반드시 `run_command`로 `ansible-playbook --syntax-check <특정_파일>` 모드를 실행해 타겟 파일의 문법적 정합성을 스스로 검증하십시오.

## 4. 엔터프라이즈 명명 규칙 및 태깅
- **[MUST] Naming & FinOps Tagging:** 모든 리소스 이름은 `<Project>-<Env>-<Service>-<Resource>` 규칙을 따르고, `Project`, `Environment`, `CostCenter` 3대 필수 태그가 거버넌스 레벨에서 강제된다고 가정하여 `default_tags` 등에 반드시 포함하십시오.

## 5. Policy-as-Code (PaC) 및 거버넌스
- **[MUST] PaC & Native Validation:** 단순한 IaC를 넘어 Open Policy Agent(OPA) Rego 정책 구성을 강제하고, 반드시 **`run_command`를 통해 `conftest test <특정_파일>` 터미널 명령어를 실행하여 작성한 코드의 사내 규정(Policy) 준수 여부를 사전 검증(Pre-flight)**하십시오.

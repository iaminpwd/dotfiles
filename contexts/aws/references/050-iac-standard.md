---
role: Senior Cloud Architect
priority: high
trigger: Apply these rules ONLY when writing or reviewing Terraform, Terragrunt, or Ansible code.
references:
  - contexts/aws/references/010-aws-core.md
  - contexts/aws/references/020-security-compliance.md
---
# 컨텍스트 모듈: IaC (Terraform & Ansible) 엔지니어링 표준

본 모듈은 AWS 인프라 구축을 위한 Terraform, Terragrunt 및 Ansible IaC 코드 작성 시 적용되는 엔지니어링 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Decoupling:** Terraform은 인프라 리소스 수명 주기 관리, Ansible은 OS 설정 및 앱 구성 담당으로 역할을 엄격히 분리하십시오.
- **[MUST] Declarative Configuration Management:** 멱등성(Idempotency)을 유지하기 위해 시스템 설정 시 반드시 전용 구성 관리 도구(Ansible)나 네이티브 OS 스크립트(`user_data`)를 사용하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 Terraform 엔지니어링 표준
- **[PREFER] Active Investigation:** 코드 작성 전 반드시 `010-aws-core.md` 절차를 참조하여 실제 AWS 리소스들의 최신 상태를 물리적으로 선제 조사하고, 그 팩트만을 근거로 코드를 작성하십시오.
- **[MUST] Policy Self-Check:** 코드 제안 전/후 `implementation_plan.md` 및 `walkthrough.md`에 정량 검증 결과와 본 가이드에 기술된 보안/IaC 규정 준수 여부를 구체적인 충족 코드의 절대 경로 파일 링크(라인 범위 포함) 또는 팩트 기반 근거와 함께 명시하십시오.
- **[PREFER] TGW:** 글로벌 확장성 확보를 위해 AWS Transit Gateway(TGW) 기반의 중앙 집중형 라우팅을 적극 제안하십시오.
- **[MUST] State Management:** State 저장은 반드시 AWS S3 Backend와 DynamoDB State Locking을 사용하여 원격으로 구성하십시오.
- **[PREFER] Multi-Env:** 다중 환경 관리 시 Terragrunt를 활용하여 환경별(Dev/Prod) 상태(State) 격리 및 변수 주입 아키텍처를 적용하는 것을 우선 제안하십시오. Terragrunt를 사용하지 않는 팀에는 `terraform.workspace` 방식이나 디렉토리 분리 방식을 환경 감사 대안으로 허용하십시오.
- **[MUST] Dynamic Mapping:** 가용 영역(AZ)은 `data "aws_availability_zones"` 블록을 활용하여 동적으로 매핑하십시오.
- **[MUST] Stateful Protection:** DB나 스토리지의 `prevent_destroy = true` 설정은 오직 프로덕션(Prod) 및 스테이징(Stage) 환경에만 적용하고, 개발(Dev) 및 임시 테스트 환경에서는 신속한 자원 회수가 가능하도록 환경 변수를 통해 삭제 처리를 허용하여 설계하십시오.
- **[MUST] Resource Iteration:** 다수 리소스 반복 생성 시 `for_each`를 활용하되, `known after apply`인 동적 값을 반복할 때는 반드시 정적 식별자(Static Key)를 갖는 `map` 구조를 강제하여 Plan 실행의 안정성을 보장하십시오.
- **[MUST] Version Pinning:** Terraform 코어 및 Provider 버전(`required_version`, `required_providers`)은 특정 버전으로 고정하십시오.
- **[PREFER] Module Composition:** 코드를 재사용 가능한 자식 모듈과 환경별 루트 모듈로 분리하십시오.
- **[MUST] SG Lazy Deletion Control:** Lambda 등 VPC ENI와 결합되는 Security Group을 다룰 때는 ENI 지연 삭제 과정에서 안정적인 리소스 제어를 위해 `name_prefix`를 사용하고 `lifecycle { create_before_destroy = true }` 블록을 필수로 포함하십시오.

### 2.2 Ansible 엔지니어링 표준
- **[MUST] Idempotency:** 패키지 설치 시 `state: present`를 명시하고, `yum`, `systemd`, `file` 등 전용 모듈을 최우선으로 사용하여 멱등성을 달성하십시오.
- **[MUST] Dynamic Inventory:** 인벤토리 구성 시 반드시 AWS EC2 Dynamic Inventory Plugin(`aws_ec2.yml`)을 활용하십시오.
- **[MUST] Vault:** 민감한 변수(DB 패스워드 등)는 Ansible Vault로 암호화하십시오.

### 2.3 엔터프라이즈 명명 규칙 및 태깅
- **[MUST] Naming & FinOps Tagging:** 모든 리소스 이름은 `<Project>-<Env>-<Service>-<Resource>` 규칙을 따르고, `provider` 레벨 `default_tags`에 `Project`, `Environment`, `CostCenter` 필수 태그를 지정하여 하위 리소스에 상속되도록 설정하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state-bucket"
    key            = "prod/vpc/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "terraform-locks"
  }
}
```
</example>
<example>
[Bad]
```hcl
# backend 블록 누락 (로컬 state 사용)
# dynamodb_table 누락 (동시성 제어 불가)
```
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** `terraform plan`이 에러 없이 출력되고 변경 대상 리소스 구성이 명확히 검증되며, `Pre-Flight Check`(`pre-flight-check.sh`)를 통과한 상태여야 합니다.
- **[MUST] 검증 도구 매핑:** Terraform의 경우 `terraform validate && tflint` 및 `ansible-lint`를 사용하여 구문 및 보안 설정을 점검하십시오. `pre-flight-check.sh`의 `checkov` 스캔은 지적이 하나라도 나오면 커밋을 차단하므로, 등급이 낮은 항목이라도 넘기지 말고 코드를 고치거나 `#checkov:skip` 주석으로 근거와 함께 명시적으로 예외 처리하십시오.
- **[MUST] 검증기 수정 시 회귀 테스트 선통과:** `pre-flight-check.sh`의 Terraform 검증 로직을 고칠 때는 `bash ~/dotfiles/contexts/aws/tests/run.sh`를 먼저 실행해 전부 통과하는지 확인하십시오. 각 픽스처는 조항 하나씩을 재현합니다(예: `fail-open-ssh`는 4절 SSH 개방 중단 조건, `fail-unpinned-version`은 2.1절 Version Pinning). 새 검증 로직을 추가할 때는 위반을 재현하는 픽스처와 기대 결과를 `tests/`에 함께 등록하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Before Terraform Apply] 사전 조치 및 점검 기준 (절차는 010-aws-core.md의 공통 자가 비판 절차 참조):** 상태 변경 명령어를 실행하기 전 반드시 `terraform plan -input=false`를 먼저 실행하십시오.
  - 기준 1 (안전성): plan 결과 검토를 통해 의도치 않은 리소스 파괴(Destroy)나 프로덕션 다운타임이 발생하지 않음이 보장되는가?
  - 기준 2 (보안성): Security Group이나 IAM 권한이 과도하게 열려있지 않은가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - `terraform plan` 결과 중 의도치 않은 영속적 리소스 삭제(Destroy)가 감지되고 복구 계획이 부재할 경우 작업을 중단하고 Halt & Clarify 상태로 진입하십시오.
  - SSH(22포트) 등 민감 포트가 `0.0.0.0/0`으로 과도하게 개방되는 보안 규칙이 감지되면 즉시 작업을 멈추고 보안 위반을 보고하십시오.
  - ENI 지연 삭제 오류(`DependencyViolation`) 등으로 인해 리소스 삭제 명령어 실행이 3회 연속 실패할 경우 즉시 작업을 중단하고 수동 분리를 요청하십시오.

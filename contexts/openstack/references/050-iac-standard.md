---
role: Senior OpenStack Architect
priority: high
trigger: Apply these rules ONLY when writing or reviewing Terraform, Heat (HOT) templates, or Ansible code for OpenStack.
references:
  - contexts/openstack/references/010-openstack-core.md
  - contexts/openstack/references/020-security-compliance.md
---
# 컨텍스트 모듈: IaC (Terraform / Heat / Ansible) 엔지니어링 표준

본 모듈은 OpenStack 인프라 구축을 위한 Terraform, Heat HOT 템플릿 및 Ansible IaC 코드 작성 시 적용되는 엔지니어링 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Decoupling:** Terraform/Heat는 인프라 리소스 수명 주기 관리, Ansible은 OS 설정 및 앱 구성 담당으로 역할을 엄격히 분리하십시오.
- **[MUST] Tool Selection:** 크로스 클라우드 이식성과 State 관리가 중요하면 Terraform(`terraform-provider-openstack`)을, OpenStack 네이티브 자동 롤백과 스택 수명 주기가 중요하면 Heat HOT를 선택하고 그 근거를 명시하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 Terraform 엔지니어링 표준
- **[PREFER] Active Investigation:** 코드 작성 전 반드시 `010-openstack-core.md` 절차를 참조하여 실제 OpenStack 리소스의 최신 상태를 물리적으로 선제 조사하고, 그 팩트만을 근거로 코드를 작성하십시오.
- **[MUST] State Management:** State는 로컬이 아닌 원격 백엔드로 구성하고 상태 잠금(state locking)을 보장하십시오. Terraform 네이티브 `swift` 백엔드는 v1.3에서 제거되었으므로 사용하지 말고, `http` 백엔드(GitLab 관리형 등) 또는 Ceph RadosGW의 S3 호환 엔드포인트(`backend "s3"` + custom endpoint, `use_lockfile = true`)를 사용하십시오.
- **[MUST] Dynamic Mapping:** Availability Zone은 하드코딩하지 말고 `data "openstack_compute_availability_zones_v2"` 블록을 활용하여 동적으로 매핑하십시오.
- **[MUST] Version Pinning:** Terraform 코어 및 Provider 버전(`required_version`, `required_providers`)은 특정 버전으로 고정하십시오.
- **[PREFER] Module Composition:** 코드를 재사용 가능한 자식 모듈과 환경별 루트 모듈로 분리하십시오.
- **[MUST] Stateful Protection:** 볼륨/DB 등 영속 리소스의 `prevent_destroy = true` 설정은 프로덕션(Prod)·스테이징(Stage)에만 적용하고, 개발(Dev)/임시 환경에서는 환경 변수로 삭제를 허용하여 신속한 자원 회수가 가능하게 설계하십시오.

### 2.2 Heat 및 Ansible 엔지니어링 표준
- **[MUST] HOT Structure:** Heat 템플릿은 `parameters`/`resources`/`outputs`를 명확히 분리하고, 리소스 간 순서는 `depends_on`과 `get_resource`/`get_attr` 참조로 명시하십시오. 민감 파라미터는 `hidden: true`로 선언하십시오.
- **[MUST] Ansible Idempotency:** OpenStack 리소스는 `openstack.cloud` 컬렉션(`os_server`, `os_network` 등) 모듈로 관리하여 멱등성을 달성하고, 인벤토리는 `openstack.cloud.openstack` 동적 인벤토리 플러그인을 활용하십시오.
- **[MUST] Vault:** 민감한 변수(DB 패스워드 등)는 Ansible Vault로 암호화하거나 Barbican에서 조회하십시오.

### 2.3 엔터프라이즈 명명 규칙 및 메타데이터
- **[MUST] Naming & Metadata Tagging:** 모든 리소스 이름은 `<Project>-<Env>-<Service>-<Resource>` 규칙을 따르고, 인스턴스/볼륨 `metadata`(또는 `properties`)에 `project`, `environment`, `cost_center` 필수 키를 지정하여 차지백 집계가 가능하게 하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
```hcl
terraform {
  # 네이티브 swift 백엔드는 Terraform 1.3에서 제거됨 → http 또는 s3(Ceph RGW) 사용
  backend "http" {
    address        = "https://gitlab.example.com/api/v4/projects/1/terraform/state/prod"
    lock_address   = "https://gitlab.example.com/api/v4/projects/1/terraform/state/prod/lock"
    unlock_address = "https://gitlab.example.com/api/v4/projects/1/terraform/state/prod/lock"
  }
}
```
</example>
<example>
[Bad]
```hcl
# backend 블록 누락 (로컬 state 사용) → 팀 협업 시 상태 충돌·유실 위험
# AZ 하드코딩 → 특정 존 장애 시 재배포 불가
```
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** `terraform plan`이 에러 없이 출력되고 변경 대상 리소스가 명확히 검증되며, Heat의 경우 `openstack orchestration template validate`를 통과하고, `Pre-Flight Check`(`pre-flight-check.sh`)를 통과한 상태여야 합니다.
- **[MUST] 검증 도구 매핑:** Terraform은 `terraform validate && tflint`, Heat는 `openstack orchestration template validate -t <template>`, Ansible은 `ansible-lint`를 사용하여 구문 및 보안 설정을 점검하십시오. `pre-flight-check.sh`의 `checkov` 스캔은 지적이 하나라도 나오면 커밋을 차단하므로, 등급이 낮은 항목이라도 넘기지 말고 코드를 고치거나 `#checkov:skip` 주석으로 근거와 함께 명시적으로 예외 처리하십시오.
- **[MUST] 검증기 수정 시 회귀 테스트 선통과:** `pre-flight-check.sh`의 Terraform 검증 로직을 고칠 때는 `bash ~/dotfiles/contexts/openstack/tests/run.sh`를 먼저 실행해 전부 통과하는지 확인하십시오. 각 픽스처는 조항 하나씩을 재현합니다(예: `fail-open-ssh`는 4절 SSH 개방 중단 조건, `fail-unpinned-version`은 2.1절 Version Pinning). 새 검증 로직을 추가할 때는 위반을 재현하는 픽스처와 기대 결과를 `tests/`에 함께 등록하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Before Terraform/Heat Apply] 사전 조치 및 점검 기준 (절차는 010-openstack-core.md의 공통 자가 비판 절차 참조):** 상태 변경 명령 실행 전 반드시 `terraform plan -input=false`(또는 Heat `stack update --dry-run`)를 먼저 실행하십시오.
  - 기준 1 (안전성): plan 결과 검토를 통해 의도치 않은 리소스 파괴(Destroy)나 프로덕션 다운타임이 발생하지 않음이 보장되는가?
  - 기준 2 (보안성): 보안 그룹이나 Keystone 역할이 과도하게 열려있지 않은가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - `terraform plan` 결과 중 의도치 않은 영속적 리소스 삭제(Destroy)가 감지되고 복구 계획이 부재할 경우 작업을 중단하고 Halt & Clarify 상태로 진입하십시오.
  - SSH(22포트) 등 민감 포트가 `0.0.0.0/0`으로 과도하게 개방되는 보안 규칙이 감지되면 즉시 작업을 멈추고 보안 위반을 보고(Hard Block)하십시오.

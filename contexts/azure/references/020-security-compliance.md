---
role: Senior Security Architect
priority: high
trigger: Apply these rules whenever writing, modifying, or auditing Azure Network Security Groups (NSGs), RBAC Roles, Secrets, or general cloud infrastructure security.
references:
  - contexts/azure/references/010-azure-core.md
---
# 컨텍스트 모듈: 시크릿 및 핵심 보안 원칙 (Security Core)

본 모듈은 클라우드 보안 거버넌스 준수 및 Azure 자격 증명, RBAC 권한 설계 시 적용되는 핵심 보안 표준 가이드라인임.

## 1. 핵심 설계 원칙
- **[MUST] Least Privilege:** RBAC 정책 작성 시 반드시 정확한 작업(Action/DataAction) 이름과 명시적인 리소스 Scope ARN을 지정하여 최소 권한을 부여할 것. 와일드카드를 사용할 경우 반드시 대상 리소스의 특정 접두사(Prefix) 범위를 한정할 것.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 자격 증명 (Secrets) 관리
- **[MUST] 시크릿 자격 증명 외부 저장소 연동 강제:** Azure Client ID/Secret이나 패스워드 등 민감한 자격 증명은 반드시 `data` 블록을 사용하여 외부 시크릿 관리 서비스(Azure Key Vault 등)에서 동적으로 로드할 것.
- **[MUST] Sensitive Output:** Terraform Output 중 민감 정보는 `sensitive = true`를 선언할 것.
- **[MUST] Pipeline OIDC:** CI/CD 파이프라인 구성 시 반드시 OIDC를 통한 단기 자격 증명(Short-lived credentials)을 사용할 것.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- 최소 권한 부여:
```json
{
  "Name": "Custom Blob Contributor",
  "IsCustom": true,
  "Actions": [],
  "DataActions": [
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read",
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write"
  ],
  "AssignableScopes": [
    "/subscriptions/{sub_id}/resourceGroups/{rg}/providers/Microsoft.Storage/storageAccounts/mysecureapp"
  ]
}
```
- 시크릿 동적 주입:
```hcl
password = data.azurerm_key_vault_secret.db_pass.value
```
</example>
<example>
[Bad]
- 과도한 권한 부여:
```json
{
  "Name": "Too Broad Role",
  "IsCustom": true,
  "Actions": [
    "*"
  ],
  "AssignableScopes": [
    "/subscriptions/{sub_id}"
  ]
}
```
- 평문 패스워드 노출:
```hcl
password = "SuperSecret123!"
```
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 모든 자격 증명 노출 위반 검사가 무결하게 통과되고, RBAC 역할의 범위가 승인된 리소스 그룹 단위로 격리되어야 합니다.
## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Azure RBAC Role Created] 점검 기준 (절차는 010-azure-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (최소 권한): 역할이 와일드카드(`*`) 없이 필요한 작업으로만 한정되어 권한 상승(Privilege Escalation) 가능성이 통제되었는가?
  - 기준 2 (자원 격리): `AssignableScopes` 구문에 명확한 리소스 Scope ID가 지정되어 리소스 격리가 보장되는가?
- **[Trigger: Security Vulnerability Found] 중단 조건 (Halt Conditions):**
  - 자격 증명(Client Secret 등)이 평문으로 파일이나 주석에 유출되었음이 감지되면 즉시 모든 작업을 중단(Hard Block)하고 유출 상태를 사용자에게 경고할 것.
  - 관리자 역할(`Owner` 등)이 불필요하게 신규 주입되는 코드가 감지되면 작업을 멈추고 보안 검토를 요청할 것.

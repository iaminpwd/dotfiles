---
role: Senior Security Architect
priority: high
trigger: Apply these rules whenever writing, modifying, or auditing AWS Security Groups, IAM Policies, Secrets, or general cloud infrastructure security.
references:
  - contexts/aws/references/010-aws-core.md
---
# 컨텍스트 모듈: 시크릿 및 핵심 보안 원칙 (Security Core)

AWS 자격 증명 및 IAM 권한 설계 시 적용되는 표준임.

## 1. 핵심 설계 원칙
- **[MUST] Least Privilege:** IAM 정책에 정확한 Action과 ARN을 지정하여 최소 권한을 부여할 것. (이유: 최소 권한 보장)

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 자격 증명 (Secrets) 관리
- **[MUST] 시크릿 외부 연동:** 민감한 자격 증명은 `data` 블록으로 시크릿 관리 서비스에서 동적 로드할 것. (이유: 시크릿 안전 보장)
- **[MUST] Sensitive Output:** Terraform Output 중 민감 정보는 `sensitive = true`를 선언할 것.
- **[MUST] Pipeline OIDC:** CI/CD 파이프라인 구성 시 반드시 OIDC를 통한 단기 자격 증명(Short-lived credentials)을 사용할 것.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- 최소 권한 부여:
```json
{
  "Action": [
    "s3:GetObject",
    "s3:PutObject"
  ],
  "Resource": "arn:aws:s3:::my-secure-app-bucket/*"
}
```
- 시크릿 동적 주입:
```hcl
password = data.aws_secretsmanager_secret_version.db_pass.secret_string
```
</example>
<example>
[Bad]
- 과도한 권한 부여:
```json
{
  "Action": "*",
  "Resource": "*"
}
```
- 평문 패스워드 노출:
```hcl
password = "SuperSecret123!"
```
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 모든 자격 증명 노출 위반 검사가 무결하게 통과되고, IAM 정책의 범위가 승인된 리소스로 격리되어야 합니다.
## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: IAM Policy Created] 점검 기준 (절차는 010-aws-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (최소 권한): 정책이 와일드카드(`*`) 없이(또는 접두사 한정으로만) 작성되어 권한 상승(Privilege Escalation) 가능성이 통제되었는가?
  - 기준 2 (자원 격리): `Resource` 구문에 명확한 ARN이 지정되어 리소스 격리가 보장되는가?
- **[Trigger: Security Vulnerability Found] 중단 조건 (Halt Conditions):**
  - 자격 증명(Access Key 등)이 평문으로 파일이나 주석에 유출되었음이 감지되면 즉시 모든 작업을 중단(Hard Block)하고 유출 상태를 사용자에게 경고할 것.
  - 관리자 권한(`AdministratorAccess`)이 불필요한 계정에 부여되거나 권한 범위가 과도한 IAM 정책 생성이 감지되면 작업을 멈추고 보안 검토를 요청할 것.

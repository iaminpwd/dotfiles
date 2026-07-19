---
role: Senior Security Architect
priority: high
trigger: Apply these rules whenever writing, modifying, or auditing AWS Security Groups, IAM Policies, Secrets, or general cloud infrastructure security.
references:
  - contexts/aws/references/010-aws-core.md
---
# 컨텍스트 모듈: 시크릿 및 핵심 보안 원칙 (Security Core)

본 모듈은 클라우드 보안 거버넌스 준수 및 AWS 자격 증명, IAM 권한 설계 시 적용되는 핵심 보안 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Least Privilege:** IAM/RBAC 정책 작성 시 반드시 정확한 작업(Action) 이름과 명시적인 리소스 ARN을 지정하여 최소 권한을 부여하십시오. 와일드카드를 사용할 경우 반드시 대상 리소스의 특정 접두사(Prefix) 범위를 한정하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 자격 증명 (Secrets) 관리
- **[MUST] 시크릿 자격 증명 외부 저장소 연동 강제:** AWS Access/Secret Key나 패스워드 등 민감한 자격 증명은 반드시 `data` 블록을 사용하여 외부 시크릿 관리 서비스(AWS Secrets Manager, SSM Parameter Store 등)에서 동적으로 로드하십시오.
- **[MUST] Sensitive Output:** Terraform Output 중 민감 정보는 `sensitive = true`를 선언하십시오.
- **[MUST] Pipeline OIDC:** CI/CD 파이프라인 구성 시 반드시 OIDC를 통한 단기 자격 증명(Short-lived credentials)을 사용하십시오.

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
- **[MUST] 검증 도구 매핑:** `trufflehog`를 사용하여 코드 내 시크릿 노출 여부를 자동 검사하고, `checkov` 또는 `tfsec`을 이용하여 보안 규칙 위반을 사전 스캔하십시오. IAM 정책을 신규 작성하거나 변경한 경우, AWS IAM Access Analyzer로 의도치 않은 외부 계정/퍼블릭 접근 허용 여부와 실사용 기준 미사용 권한(Unused Access)을 추가로 검증하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: IAM Policy Created] 도메인 자가 채점:** IAM 정책 초안 작성을 완료한 직후, 스스로 `<self_critique>` 태그를 열어 아래 2가지 점검 기준으로 1~5점 자가 채점을 수행하고 사유를 명시하십시오. (두 기준 모두 5점 만점일 때만 작업을 승인 요청하십시오)
  - 기준 1 (최소 권한): 정책 내에 와일드카드(`*`)가 포함되어 권한 상승(Privilege Escalation) 가능성이 존재하는가?
  - 기준 2 (자원 제한): `Resource` 구문에 명확한 ARN이 지정되어 리소스 격리가 보장되는가?
- **[Trigger: Security Vulnerability Found] 중단 조건 (Halt Conditions):**
  - 자격 증명(Access Key 등)이 평문으로 파일이나 주석에 유출되었음이 감지되면 즉시 모든 작업을 중단(Hard Block)하고 유출 상태를 사용자에게 경고하십시오.
  - 관리자 권한(`AdministratorAccess`)이 불필요한 계정에 부여되거나 권한 범위가 과도한 IAM 정책 생성이 감지되면 작업을 멈추고 보안 검토를 요청하십시오.

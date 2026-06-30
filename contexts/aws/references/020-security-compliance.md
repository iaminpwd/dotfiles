---
role: Senior Security Architect
priority: high
---
<!-- 의도: 시크릿/보안 규칙은 domain_specific_rules 없이 Global Core로 모든 작업에 항상 적용 -->
# 컨텍스트 모듈: 020. 시크릿 및 핵심 보안 원칙 (Security Core)

## 1. 자격 증명 (Secrets) 관리
- **[MUST] 시크릿 자격 증명 외부 저장소 연동 강제:** AWS Access/Secret Key나 패스워드 등 민감한 자격 증명은 반드시 `data` 블록을 사용하여 외부 시크릿 관리 서비스(AWS Secrets Manager, SSM Parameter Store 등)에서 동적으로 로드하십시오.
- **[MUST] Sensitive Output:** Terraform Output 중 민감 정보는 `sensitive = true`를 선언하십시오.
- **[MUST] Pipeline OIDC:** CI/CD 파이프라인 구성 시 반드시 OIDC를 통한 단기 자격 증명(Short-lived credentials)을 사용하십시오.
- **[Trigger: Before Code Review / Commit] 시크릿 스캐닝:** 코드를 작성하거나 리뷰할 때 반드시 `run_command`로 `trufflehog filesystem <특정_경로>` 스캐닝을 실행하여 하드코딩된 시크릿을 사전에 차단하십시오.

## 2. 최소 권한 및 데이터 보안 (Least Privilege & Data Security)
- **[MUST] 명시적 최소 권한 부여 (Least Privilege):** IAM/RBAC 정책 작성 시, 반드시 정확한 작업(Action) 이름과 명시적인 리소스 ARN을 지정하여 최소 권한을 부여하십시오.

### 최소 권한 부여 예시 (Few-Shot Examples)
<examples>
<example>
[Good]
```json
{
  "Action": [
    "s3:GetObject",
    "s3:PutObject"
  ],
  "Resource": "arn:aws:s3:::my-secure-app-bucket/*"
}
```
</example>
<example>
[Bad]
```json
{
  "Action": "*",
  "Resource": "*"
}
```
</example>
</examples>

### 시크릿 동적 주입 예시 (Few-Shot Examples)
<examples>
<example>
[Good]
```hcl
password = data.aws_secretsmanager_secret_version.db_pass.secret_string
```
</example>
<example>
[Bad]
```hcl
password = "SuperSecret123!" # 하드코딩 절대 금지
```
</example>
</examples>

- **[Trigger: IAM Policy Created] 자가 비판 (Self-Critique):** IAM 정책 초안 작성을 완료한 직후, 스스로 `<self_critique>` 태그를 열어 **와일드카드(`*`) 사용으로 인한 권한 상승(Privilege Escalation) 가능성 및 의도치 않은 리소스 접근 위험성**을 집중 비판하십시오.

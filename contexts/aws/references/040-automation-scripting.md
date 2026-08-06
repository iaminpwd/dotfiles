---
role: Senior DevOps Automation Engineer
priority: high
trigger: Apply these rules ONLY when writing shell scripts (Bash/Zsh), automating tasks, or installing system CLI tools.
references:
  - contexts/aws/references/010-aws-core.md
  - contexts/prompt-architect/references/020-shell-scripting-standard.md
---
# 컨텍스트 모듈: 시스템 자동화 및 셸 스크립트(Bash) 엔지니어링 표준

범용 Bash 안전성 규칙(strict mode, 멱등성, 백업, user-level 설치, 진행 로깅, WSL2 대응, pipx/mise 도구 격리 등)은 `prompt-architect/020-shell-scripting-standard.md`가 SSOT임 — 본 문서는 AWS 자동화 스크립트(`aws cli`, `boto3` 셋업 스크립트 등)에서 그 표준 위에 추가로 필요한 AWS 고유 사항만 기재한다.

## 1. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[MUST] 중단 조건 (Halt Conditions):**
  - `aws ec2 terminate-instances`, `aws s3 rm --recursive`, `aws rds delete-db-instance` 등 `aws cli` 파괴적 명령이 대상 필터(태그, 리소스 ID 명시 등) 검증 없이 광역으로 실행되는 스크립트가 감지될 시 작업을 멈추고 안전장치 추가를 요구할 것. (Terraform으로 관리되는 리소스의 `terraform destroy` 보호는 `050-iac-standard.md` 참조)

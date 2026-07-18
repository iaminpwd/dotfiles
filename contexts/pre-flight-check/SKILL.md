---
name: Pre-Flight Check
description: |
  Terraform, Ansible, Bicep, Helm, Dockerfile 등 모든 인프라 코드 및 쉘 스크립트 작성 시
  공통적으로 작동되는 정량적 검증 파이프라인(pre-flight-check.sh) 가이드 스킬입니다.
---
# 사전 검증 스킬 (Pre-Flight Check)

본 스킬은 Terraform, Ansible, Azure Bicep, AWS SAM, Kubernetes Helm, Dockerfile 또는 일반 자동화 쉘 스크립트(`.sh`, `.zsh`) 코드를 작성, 수정 또는 리뷰할 때 공통으로 활성화되어 적용됩니다.

## 1. 정량적 일괄 검증 파이프라인 (Automated Validation)

- **[MUST] pre-flight-check.sh 템플릿 복사 및 실행:** 인프라 및 스크립트 코드가 수정된 후, 개별 도구(tflint, trivy 등)를 분산 실행하지 마십시오. 작업 중인 프로젝트의 루트 디렉토리에 `pre-flight-check.sh`가 존재하지 않는 경우, 본 스킬 하위의 `scripts/pre-flight-check.sh` 템플릿 파일을 프로젝트 루트로 복사한 뒤 실행하십시오.
  *   복사된 `pre-flight-check.sh`는 글로벌 Git 무시 설정(`.gitignore_global`)에 의해 Git 추적에서 자동으로 제외되므로 안심하고 사용하십시오.
  *   `run_command`를 통해 `./pre-flight-check.sh`를 단일 실행하여 포맷(fmt), 유효성(validate), 정적 분석(tflint), 보안/시크릿 스캔(trivy/trufflehog), 문서화(terraform-docs) 등을 일괄 수행하십시오.

## 2. 정성적 정책 자가 검증 (Policy Self-Check)

- **[MUST] Policy Self-Check Table (근거 제시 필수):** 코드 제안 및 작업 완료 보고 시, `implementation_plan.md` 및 `walkthrough.md`에 기술적인 검증 결과(pre-flight-check.sh 패스 여부)뿐만 아니라 개별 클라우드 표준(AWS/Azure 등)에 정의된 정성적 가이드라인(예: 백엔드 상태 잠금 적용 여부, 최소 권한 보안 그룹 구성, 리소스 명명 규칙 등)의 준수 여부를 나타내는 자가 체크리스트 테이블을 명시적으로 수록하여 보고하십시오.
  *   **[CRITICAL]** 단순히 '준수함'으로 기재하지 마십시오. 테이블의 각 점검 항목에 준수 여부(Pass/N/A)뿐만 아니라, **해당 규칙을 충족하는 구체적인 코드 위치의 절대 경로 파일 링크(라인 번호 범위 포함, 예: [main.tf:L5-12](file:///home/ubuntu/workspace/main.tf#L5-L12)) 또는 실제 CLI 실행 근거**를 상세 컬럼으로 추가하여 물리적으로 입증해야 합니다. 근거 파일 링크가 누락된 준수 표기는 환각(Hallucination)으로 간주되어 전체 승인이 거부됩니다.
  *   **[REQUIRED TEMPLATE]** Policy Self-Check 테이블 작성 시 반드시 아래 템플릿 구조와 헤더 컬럼명을 사용하고, 예시 경로가 아닌 **실제 수정된 파일의 절대 경로**를 `file:///` 프로토콜 뒤에 정확히 매핑하십시오.
      ```markdown
      ### 정성적 정책 자가 검증 (Policy Self-Check)

      | 점검 항목 (Policy Item) | 준수 여부 (Status) | 물리적 근거 및 코드 링크 (Evidence & Code Link) | 상세 설명 (Notes) |
      | :--- | :--- | :--- | :--- |
      | (예시) S3 Backend / DynamoDB Lock | Pass | [backend.tf:L3-10](file:///home/ubuntu/dotfiles/terraform/backend.tf#L3-L10) | DynamoDB 원격 상태 잠금이 구성됨 |
      | (예시) 최소 권한 Security Group | Pass | [security.tf:L12-30](file:///home/ubuntu/dotfiles/terraform/security.tf#L12-L30) | 인바운드는 사내 VPN CIDR 대역으로만 제한됨 |
      | [실제 점검 항목 기재] | Pass/N/A | [실제 물리 절대 경로 링크](file:///실제절대경로#L시작-L종료) | 실제 준수 여부 근거 요약 |
      ```



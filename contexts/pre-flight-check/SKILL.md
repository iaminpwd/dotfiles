---
name: pre-flight-check
description: |
  인프라 및 자동화 코드에 대한 정량적 사전 검증(Pre-Flight Check) 및 린트/정적 분석 파이프라인 스킬임.
  Terraform, Ansible, Helm, Dockerfile 등 모든 인프라 코드 및 쉘 스크립트 작성/수정 후 
  안전성과 멱등성을 검증할 때 공통적으로 작동해야 합니다.
---
# 사전 검증 스킬 (Pre-Flight Check)

인프라 코드 및 자동화 스크립트 작성/수정 시 공통 적용되는 표준임.

## 1. 정량적 일괄 검증 파이프라인 (Automated Validation)

편집 직후(`pre-flight-live-hook.sh`, PostToolUse)와 완료 선언 직전(`pre-flight-gate-hook.sh`, Stop)에 `pre-flight-check.sh`가 자동으로 실행되므로 수동 호출은 필요 없습니다. 이 두 훅이 닿지 않는 범위(옵트인 대상 밖의 저장소 등)에서만 `run-suite.sh --pfc-args="--changed"` (또는 `just check`)를 직접 실행할 것.

- 이 `pre-flight-check.sh` 스크립트는 terraform fmt, init, validate를 완전히 대체(Replace)하는 통합 검증 파이프라인으로 작동합니다. 정적 분석(tflint), 보안/시크릿 스캔(trivy/trufflehog) 등이 함께 일괄 수행됩니다. **비용 분석(infracost breakdown 기반 Extended Support 연장 요금 검증)** 은 별도로 `RUN_COST_CHECK=true` 환경 변수가 설정된 경우에만 수행되며, 이 변수는 현재 `git/.githooks/pre-commit`(실제 git 커밋 시점)에서만 자동으로 설정됩니다. 훅 자동 실행이든 터미널 수동 실행이든 비용 분석은 기본적으로 건너뛰어지므로, 확인하려면 `RUN_COST_CHECK=true run-suite.sh --pfc-args="--changed"`처럼 명시적으로 변수를 설정할 것.
- **[MUST] 종료 코드 기준 판정:** 래퍼는 각 스크립트의 종료 코드로만 합격을 판정하며, 통과 항목은 `-> [✓] <경로>` 한 줄로 접고 실패 항목은 압축 없이 원형 로그를 출력함. 실패가 있어도 남은 항목을 끝까지 실행한 뒤 마지막에 `검증 실패 N/M` 을 남기므로, **마지막 요약 줄과 종료 코드까지 반드시 확인**하십시오. 통과 항목이라도 `[WARNING]` 은 접지 않으므로, 도구 미설치로 검증이 건너뛰어졌는지 함께 확인할 것. (래퍼 자신의 회귀 테스트: `contexts/dotfiles/tests/test-run-suite.sh`)
- **[MUST] 자율 자가 치유 시 연쇄 종속성 동시 수정:** `run-suite.sh` 검증 실패로 인해 에이전트가 자가 치유(Self-Healing)를 시도할 때, 특정 리소스(예: AWS RDS)의 엔진 버전을 올리는 경우 연관된 종속성 속성(예: `parameter_group_name`, `option_group_name` 등)을 해당 엔진 버전에 호환되는 규격으로 함께 변경하여 2차 유효성 검사(tflint, terraform validate 등)를 통과하도록 할 것.
- **[MUST] Checkov 예외 처리:** `checkov` 스캔 결과 보안 정책상 불가피하게 수정이 불가능한 항목은 반드시 해당 리소스 블록 위에 `#checkov:skip=<Rule ID>: <근거>` 형태의 주석과 명확한 사유를 기재하여 예외 처리할 것.

## 2. 정성적 정책 자가 검증 (Policy Self-Check)

- **[MUST] Policy Self-Check Table (자가 검증 테이블 필수):** 작업 완료 보고 시(`walkthrough.md` 등) 아래 템플릿을 사용하여 클라우드 표준 정책 준수 여부를 테이블로 작성할 것.
  * **[CRITICAL] 물리적 근거 기입 필수:** 준수 여부(Status) 기록 시, 반드시 해당 규칙을 충족하는 구체적인 코드 절대 경로 및 라인 범위 링크(예: [main.tf:L5-12](file:///$HOME/workspace/main.tf#L5-L12)) 또는 CLI 실행 결과를 명시할 것. 근거 링크가 누락된 항목은 검증 실패로 간주되어 승인되지 않습니다.
  * **[CRITICAL] 웹 검색 기반 값의 출처 근거 병기 필수:** 엔진/런타임 버전 등 웹 검색으로 사실 확인이 요구되는 항목(예: Extended Support 회피를 위한 최신 표준 지원 버전 확정)은, 코드 링크만으로는 실제 검색 수행 여부를 감사할 수 없으므로 "물리적 근거 및 코드 링크" 컬럼에 코드 라인 링크와 함께 **검색 출처 URL 및 조회 일자**를 반드시 병기할 것. 코드 라인 링크만 있고 검색 출처가 누락된 항목은 검증 실패로 간주되어 승인되지 않습니다.
  * **[REQUIRED TEMPLATE]** 테이블 작성 시 반드시 아래 템플릿 구조와 헤더 컬럼명을 사용하고, 예시 경로가 아닌 **실제 수정된 파일의 절대 경로**를 `file:///` 프로토콜 뒤에 정확히 매핑할 것.
      ```markdown
      ### 정성적 정책 자가 검증 (Policy Self-Check)

      | 점검 항목 (Policy Item) | 준수 여부 (Status) | 물리적 근거 및 코드 링크 (Evidence & Code Link) | 상세 설명 (Notes) |
      | :--- | :--- | :--- | :--- |
      | (예시) S3 Backend / DynamoDB Lock | Pass | [backend.tf:L3-10](file:///$HOME/dotfiles/terraform/backend.tf#L3-L10) | DynamoDB 원격 상태 잠금이 구성됨 |
      | (예시) 최소 권한 Security Group | Pass | [security.tf:L12-30](file:///$HOME/dotfiles/terraform/security.tf#L12-L30) | 인바운드는 사내 VPN CIDR 대역으로만 제한됨 |
      | [실제 점검 항목 기재] | Pass/N/A | [실제 물리 절대 경로 링크](file:///실제절대경로#L시작-L종료) | 실제 준수 여부 근거 요약 |
      ```

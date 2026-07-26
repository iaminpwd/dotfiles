---
name: pre-flight-check
description: |
  Terraform, Ansible, Helm, Dockerfile 등 모든 인프라 코드 및 쉘 스크립트 작성 시
  공통적으로 작동되는 정량적 검증 파이프라인(pre-flight-check.sh) 가이드 스킬입니다.
reviewed: 2026-07-21
---
# 사전 검증 스킬 (Pre-Flight Check)

본 스킬은 Terraform, Ansible, AWS SAM, Kubernetes Helm, Dockerfile 또는 일반 자동화 쉘 스크립트(`.sh`, `.zsh`) 코드를 작성, 수정 또는 리뷰할 때 공통으로 활성화되어 적용됩니다.

## 1. 정량적 일괄 검증 파이프라인 (Automated Validation)

- **[MUST] pre-flight-check.sh 심볼릭 링크 연결 및 실행:** 인프라 및 스크립트 코드가 수정된 후, `pre-flight-check.sh` 단일 스크립트로 검증(tflint, trivy 등)을 통합 실행하십시오. 작업 중인 프로젝트의 루트 디렉토리에 `pre-flight-check.sh`가 존재하지 않는 경우, 본 스킬 하위의 `scripts/pre-flight-check.sh` 원본을 가리키는 **심볼릭 링크를 프로젝트 루트에 생성**(`ln -sf [원본경로] ./pre-flight-check.sh`)하여 사용하십시오.
  *   **[PREFER] Symbolic Link Over Copy:** 도트파일 원본의 검증 로직 업데이트 사항이 실시간으로 모든 작업 저장소에 자동 동기화되도록 심볼릭 링크 생성을 최우선으로 시도하고, 파일 시스템 제약 등으로 불가능한 환경에 한해서만 물리 복사(`cp`)를 차선책으로 우회 수행하십시오.
  *   터미널에서 `./pre-flight-check.sh`를 단일 실행하여 포맷(fmt), 유효성(validate), 정적 분석(tflint), 보안/시크릿 스캔(trivy/trufflehog) 및 **비용 분석(infracost breakdown 기반 Extended Support 연장 요금 검증)** 등을 일괄 수행하십시오.
  *   **[MUST] 자율 자가 치유 시 연쇄 종속성 동시 수정:** `pre-flight-check.sh` 검증 실패로 인해 에이전트가 자가 치유(Self-Healing)를 시도할 때, 특정 리소스(예: AWS RDS)의 엔진 버전을 올리는 경우 연관된 종속성 속성(예: `parameter_group_name`, `option_group_name` 등)을 해당 엔진 버전에 호환되는 규격으로 함께 변경하여 2차 유효성 검사 실패(tflint, terraform validate 등)를 방지하십시오.



## 2. 정성적 정책 자가 검증 (Policy Self-Check)

- **[MUST] Policy Self-Check Table (자가 검증 테이블 필수):** 작업 완료 보고 시(`walkthrough.md` 등) 아래 템플릿을 사용하여 클라우드 표준 정책 준수 여부를 테이블로 작성하십시오.
  * **[CRITICAL] 물리적 근거 기입 필수:** 준수 여부(Status) 기록 시, 반드시 해당 규칙을 충족하는 구체적인 코드 절대 경로 및 라인 범위 링크(예: [main.tf:L5-12](file:///$HOME/workspace/main.tf#L5-L12)) 또는 CLI 실행 결과를 명시하십시오. 근거 링크가 누락된 항목은 검증 실패로 간주되어 승인되지 않습니다.
  * **[CRITICAL] 웹 검색 기반 값의 출처 근거 병기 필수:** 엔진/런타임 버전 등 웹 검색으로 사실 확인이 요구되는 항목(예: Extended Support 회피를 위한 최신 표준 지원 버전 확정)은, 코드 링크만으로는 실제 검색 수행 여부를 감사할 수 없으므로 "물리적 근거 및 코드 링크" 컬럼에 코드 라인 링크와 함께 **검색 출처 URL 및 조회 일자**를 반드시 병기하십시오. 코드 라인 링크만 있고 검색 출처가 누락된 항목은 검증 실패로 간주되어 승인되지 않습니다.
  * **[REQUIRED TEMPLATE]** 테이블 작성 시 반드시 아래 템플릿 구조와 헤더 컬럼명을 사용하고, 예시 경로가 아닌 **실제 수정된 파일의 절대 경로**를 `file:///` 프로토콜 뒤에 정확히 매핑하십시오.
      ```markdown
      ### 정성적 정책 자가 검증 (Policy Self-Check)

      | 점검 항목 (Policy Item) | 준수 여부 (Status) | 물리적 근거 및 코드 링크 (Evidence & Code Link) | 상세 설명 (Notes) |
      | :--- | :--- | :--- | :--- |
      | (예시) S3 Backend / DynamoDB Lock | Pass | [backend.tf:L3-10](file:///$HOME/dotfiles/terraform/backend.tf#L3-L10) | DynamoDB 원격 상태 잠금이 구성됨 |
      | (예시) 최소 권한 Security Group | Pass | [security.tf:L12-30](file:///$HOME/dotfiles/terraform/security.tf#L12-L30) | 인바운드는 사내 VPN CIDR 대역으로만 제한됨 |
      | [실제 점검 항목 기재] | Pass/N/A | [실제 물리 절대 경로 링크](file:///실제절대경로#L시작-L종료) | 실제 준수 여부 근거 요약 |
      ```



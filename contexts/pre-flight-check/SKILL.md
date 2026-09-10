---
name: pre-flight-check
description: |
  인프라 및 자동화 코드에 대한 정량적 사전 검증(Pre-Flight Check) 및 린트/정적 분석 파이프라인 스킬임.
  Terraform, Ansible, Helm, Dockerfile 등 모든 인프라 코드 및 쉘 스크립트 작성/수정 후 
  안전성과 멱등성을 검증할 때 공통적으로 작동함.
---
# 사전 검증 스킬 (Pre-Flight Check)

인프라 코드 및 자동화 스크립트 작성/수정 시 공통 적용되는 표준임.

## 1. 정량적 일괄 검증 파이프라인 (Automated Validation)

편집 직후 검사는 기본 비활성화입니다. 완료 훅(`pre-flight-gate-hook.sh`, Stop)은 마지막 성공 검증 이후 변경 내용이 달라졌을 때 `pre-flight-check.sh --changed`를 실행합니다. 훅이 비활성화되어 있거나 실행 결과가 없으면 관련 파일에 대해 수동 검증할 것.

- 커밋 훅은 스테이징된 시크릿을 별도로 검사하고 `PFC_PROFILE=quick`으로 셸·YAML·Dockerfile 린트와 Terraform 포맷만 검사합니다. quick 통과는 전체 인프라 검증 통과를 뜻하지 않습니다.
- 기본 `full` 프로필은 Terraform 초기화·validate, 인프라 및 보안 검사도 실행합니다. CI의 `PFC_PROFILE=full just verify`는 전체 파일과 회귀 스위트를 검증합니다.
- pre-push 회귀 테스트는 `DOTFILES_PRE_PUSH=1 git push`로 선택 실행합니다. 비용 API 검사는 커밋·푸시에서 자동으로 켜지 않으며 `RUN_COST_CHECK=true`를 명시한 경우에만 실행합니다.

- **[MUST] 종료 코드 기준 판정:** 래퍼는 각 스크립트의 종료 코드로만 합격을 판정하며, 통과 항목은 `-> [✓] <경로>` 한 줄로 접고 실패 항목은 압축 없이 원형 로그를 출력함. 실패가 있어도 남은 항목을 끝까지 실행한 뒤 마지막에 `검증 실패 N/M` 을 남기므로, **마지막 요약 줄과 종료 코드까지 반드시 확인**하십시오. 통과 항목이라도 `[WARNING]` 은 접지 않으므로, 도구 미설치로 검증이 건너뛰어졌는지 함께 확인할 것. (래퍼 자신의 회귀 테스트: `contexts/dotfiles/tests/test-run-suite.sh`)
- **[MUST] 자율 자가 치유 시 연쇄 종속성 동시 수정:** `run-suite.sh` 검증 실패로 인해 에이전트가 자가 치유(Self-Healing)를 시도할 때, 특정 리소스(예: AWS RDS)의 엔진 버전을 올리는 경우 연관된 종속성 속성(예: `parameter_group_name`, `option_group_name` 등)을 해당 엔진 버전에 호환되는 규격으로 함께 변경하여 2차 유효성 검사(tflint, terraform validate 등)를 통과하도록 할 것.
- **[MUST] Checkov 예외 처리:** `checkov` 스캔 결과 보안 정책상 불가피하게 수정이 불가능한 항목은 반드시 해당 리소스 블록 위에 `#checkov:skip=<Rule ID>: <근거>` 형태의 주석과 명확한 사유를 기재하여 예외 처리할 것.

## 2. 검증 결과 보고

- **[MUST] 검증 근거:** 현재 변경에 해당하는 검사 결과와 미실행 항목을 보고할 것. 정책 판단에는 관련 코드 위치 또는 실행 결과를 연결하고, 웹에서 확인한 버전·지원 기간 등의 값에는 출처와 조회 일자를 함께 제공할 것.
- **[PREFER] 보고 형식:** 간단한 변경은 짧은 설명으로 보고할 것. 여러 정책을 비교하거나 사용자가 감사 보고서를 요청한 경우에는 표를 사용할 것. 별도 보고서 파일과 고정 열 이름은 필수가 아님.

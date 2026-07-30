---
name: prompt-architect
description: |
  전역 AI 프롬프트 엔지니어링, 룰북(AGENTS.md, SKILL.md) 작성, 범용 쉘 스크립트 작성 표준 지침.
  어느 워크스페이스에서든 AI 프롬프트를 수정하거나 범용 쉘 스크립트를 작성할 때 항상 발동됨.
---
# Prompt Architect Skill

이 스킬은 AI 프롬프트를 설계하고 범용 쉘 스크립트를 작성할 때 고도의 표준을 적용하기 위해 전역적으로 로드되는 지침 모음입니다.

## 1. 작업 유형별 참조 문서 라우팅 (SSOT)

| 작업 유형 | 참조 문서 |
|---|---|
| AI 프롬프트 설계(Meta-Prompting) 마스터 가이드 | references/030-prompt-engineering-standard.md |
| 범용 AI 프롬프트 작성·수정·최적화 표준 | references/040-general-prompt-authoring-standard.md |
| 룰북 조항 추가·검토·삭제 가이드 | references/050-rule-provenance-standard.md |
| 쉘 스크립팅(bash/zsh) 범용 표준 | references/020-shell-scripting-standard.md |

* **공통 시스템 원칙**: references/010-core.md

## 2. 작업 프로세스 제약 (Operational Gate)

- **[MUST] 토큰 소모 검증의 사전 승인 (Paid Eval Gate)**: `contexts/prompt-architect/evals/routing/measure.sh`는 케이스 1회당 실제 에이전트 세션을 띄워 토큰을 소모함. 사용자가 이 스크립트 실행을 명시적으로 요청한 경우에만 실행하고, 그 외에는 무료 로컬 검사(`contexts/prompt-architect/evals/routing/run.sh`의 description 용어 중복 분석, `prompt-lint.sh`)로 대체할 것. description을 수정한 뒤 효과를 확인해야 한다면, 전체 재측정 대신 관련 케이스 ID만 인자로 지정한 부분 측정을 사용자에게 비용(예정 세션 수)과 함께 제안할 것.
- **[MUST] 프롬프트 코퍼스 정합성 검증 (Prompt Lint)**: `contexts/*/SKILL.md` 또는 `contexts/*/references/*.md` 파일을 신규 작성하거나 수정한 직후, 터미널에서 `prompt-lint.sh` 명령어를 실행하여 자가비판 SSOT 모듈 목록 일치, 참조 링크 무결성, 크로스 벤더 용어 오염, 코드펜스 짝, 크로스 스킬 개념 중복 후보를 정량 검증할 것. ERROR 항목은 완료 선언 전에 반드시 해결하고, WARNING 항목은 실제 중복인지 검토한 뒤 필요 시 SSOT 위임 구조로 정리할 것.
- **[MUST] 린터 자가 검증 (Linter Regression Test)**: `bin/linters/prompt-lint.sh` 로직 자체를 수정한 직후에는 반드시 `bash ~/dotfiles/contexts/prompt-architect/tests/run.sh`를 실행해 회귀 테스트를 통과해야 한다.

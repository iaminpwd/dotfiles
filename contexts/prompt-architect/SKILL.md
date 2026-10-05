---
name: prompt-architect
description: |
  AI 프롬프트와 룰북(AGENTS.md, SKILL.md)을 작성·검토·간소화할 때 사용하는 스킬.
  일반 셸 코드 수정만으로는 호출하지 않으며, 셸 작성 기준은 필요할 때 참조할 수 있음.
---
# Prompt Architect Skill

프롬프트 또는 쉘 스크립트 작업에 해당하는 참조 문서만 선택해 읽습니다. 연결된 문서는 현재 판단에 필요한 경우에만 추가로 읽습니다.

## 1. 작업 유형별 참조 문서 라우팅 (SSOT)

| 작업 유형 | 참조 문서 |
|---|---|
| AI 프롬프트 설계(Meta-Prompting) 마스터 가이드 | references/030-prompt-engineering-standard.md |
| 범용 AI 프롬프트 작성·수정·최적화 표준 | references/040-general-prompt-authoring-standard.md |
| 룰북 조항 추가·검토·삭제 가이드 | references/050-rule-provenance-standard.md |
| 쉘 스크립팅(bash/zsh) 범용 표준 | references/020-shell-scripting-standard.md |

* **공통 시스템 원칙**: references/010-core.md

## 2. 검증

- `contexts/` 프롬프트 변경 후 원본 저장소에서 `bash bin/linters/prompt-lint.sh`를 실행한다. 오류는 해결하고 경고는 실제 영향과 미검증 범위를 확인한다.
- 라우팅 표 변경 후 `just docs-index`, description 변경 후 `bash contexts/prompt-architect/evals/routing/run.sh --check-cases-only`로 정합성을 확인한다. 정적 검사는 실제 모델의 호출 정확도를 증명하지 않는다.
- 린터 로직 변경은 `bash contexts/prompt-architect/tests/run.sh`로 회귀 검증한다.
- **[MUST] 유료 평가:** `contexts/prompt-architect/evals/routing/measure.sh`는 실제 에이전트 세션을 실행한다. 사용자가 명시적으로 실행을 요청한 경우에만 수행한다. 그 외에는 로컬 정답지·description 분석을 사용한다.

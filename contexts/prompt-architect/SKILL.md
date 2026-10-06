---
name: prompt-architect
description: |
  AI 프롬프트와 룰북(AGENTS.md, SKILL.md)을 작성·검토·간소화할 때 사용하는 검증 스킬.
---
# Prompt QA Skill

프롬프트 작성법을 다시 가르치지 않는다. 저장소 고유 계약과 실행 가능한 검증만 확인한다.

## 검증

- `contexts/`의 프롬프트·룰북 변경 후 `bash bin/linters/prompt-lint.sh`를 실행한다.
- SKILL 라우팅 변경 후 `just docs-index`, description 변경 후 `bash contexts/prompt-architect/evals/routing/run.sh --check-cases-only`를 실행한다.
- `bin/linters/prompt-lint.sh` 로직 변경 후 `bash contexts/prompt-architect/tests/run.sh`로 회귀 검증한다.
- 규칙을 추가할 때는 모델의 일반 지식보다 저장소 고유 경로·출력 계약·실제 실패 방지책을 우선한다.
- 정적으로 판정 가능한 조건은 문서 규칙보다 테스트·린터로 강제한다.
- `contexts/prompt-architect/evals/routing/measure.sh`는 실제 에이전트 세션 비용이 발생하므로 사용자가 명시적으로 요청한 경우에만 실행한다.

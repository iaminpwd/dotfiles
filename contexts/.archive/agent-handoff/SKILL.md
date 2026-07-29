---
name: agent-handoff
description: |
  Claude(아키텍트)와 Gemini(실행자)가 파일을 주고받으며 협업하는 핸드오프 프로토콜.
  "설계도 만들어줘", "계획대로 실행해", "제미나이한테 넘겨", "핸드오프로 진행"
  같은 요청이나, 작업 디렉토리에 Claude-to-Gemini.md 또는 Gemini-to-Claude.md 가
  있을 때 사용하십시오.
---
# Agent Handoff Protocol

본 룰의 발동 조건은 base.AGENTS.md의 역할을 배타적으로 수용하십시오.

**[역할 확정] 이 문서 하단에는 당신의 역할 지침 한 벌만 포함되어 있습니다.** `setup.sh`
가 배포 시점에 이 공통부와 역할 파일(`role.architect.md` 또는 `role.executor.md`) 중
한 벌만 결합해 배포본을 생성하므로, 상대 역할의 지침은 이 문서에 존재하지 않습니다.
오직 배포본에 결합된 본인의 역할 지침 단 하나만을 절대적 SSOT로 신뢰하십시오.

## 공통 규약 (Shared Contract)
- **[MUST] 통신 파일 경로 고정**: 설계도(`Claude-to-Gemini.md`), 결과 리포트(`Gemini-to-Claude.md`)를 루트에 생성하고 아카이브는 `.agent-state/handoff-archive/<task-id>/`에 격리하십시오. (이유: 파일 충돌 방지)
- **[MUST] task-id 는 작업 단위**: `<task-id>`는 동일 작업 시 누적 유지하십시오. (이유: 3왕복 상한선 회피 무한 루프 방어)

## 검증 및 중단 조건 (Success & Halt Criteria)
- **[MUST] 완료 조건**: `Gemini-to-Claude.md`가 SUCCESS이며, 아키텍트가 대상 파일에서 직접 반영을 교차 검증한 경우에만 완료를 선언하십시오. (이유: 환각성 허위 보고 차단)
- **[MUST] 배포 반영 확인**: 이 프로토콜은 다른 스킬처럼 심볼릭 링크로 노출되지 않고,
  `setup.sh` 가 공통부와 역할 파일을 결합한 **복사본** 두 벌
  (`~/.claude/skills/agent-handoff/`, `~/.gemini/config/skills/agent-handoff/`)로
  배포됩니다. 따라서 저장소의 원본을 수정해도 재배포 전까지는 양측 에이전트의 런타임에
  반영되지 않습니다. 원본을 수정한 턴은 아래
  명령으로 즉시 재배포하고, `--check` 가 종료 코드 0 을 내는 것을 확인한 뒤에야 개정 완료를
  선언하십시오. `setup.sh` 전체를 다시 돌릴 필요는 없습니다.
  ```bash
  bash contexts/agent-handoff/scripts/deploy.sh
  bash contexts/agent-handoff/scripts/deploy.sh --check
  ```
  커밋 시점에는 `git/.githooks/pre-commit` 이 같은 스크립트로 드리프트를 자가 치유하지만,
  그것은 다음 세션을 위한 안전망입니다. 현재 세션에서 개정 조항이 즉시 적용되려면 원본을
  고친 직후 직접 재배포해야 합니다.
- **[MUST] 중단 조건 (3왕복 상한)**: `.agent-state/handoff-archive/<task-id>/` 내 파일이 6개
  (3왕복)를 초과하면 양 에이전트는 즉시 모든 작업을 중단하고, 지금까지의 경과와 Blockers
  를 사용자에게 브리핑해 개입을 요청하십시오.
- **[MUST] 기계 검증 실행**: 위 상한과 트리거 해제 여부는 조항 문장이 아니라
  `contexts/agent-handoff/scripts/handoff-check.sh` 가 판정합니다. 양 에이전트는 통신 파일을
  쓰거나 소비한 직후 이 스크립트를 실행해 통과를 확인하십시오. 통신 파일 동시 존재와
  `task-id` 누락은 ERROR 로 커밋까지 차단됩니다(`git/.githooks/pre-commit`). 3왕복 상한
  초과는 에이전트가 직접 호출할 때만 ERROR 이며(루프를 멈추라는 조건이므로), 커밋 게이트
  에서는 경고로만 표시됩니다. 상한에 걸린 시점에는 지금까지의 작업을 커밋해 두고 사용자에게
  개입을 요청하는 것이 정상 흐름이기 때문입니다.
  핸드오프 산출물이 없는 저장소에서는 아무 출력 없이 통과하므로 무관한 작업을 방해하지
  않습니다. 회귀 픽스처는 `contexts/agent-handoff/tests/run.sh` 로 실행합니다.

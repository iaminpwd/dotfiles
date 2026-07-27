---
name: agent-handoff
description: |
  Claude(아키텍트)와 Gemini(실행자)가 파일을 주고받으며 협업하는 핸드오프 프로토콜.
  "설계도 만들어줘", "계획대로 실행해", "제미나이한테 넘겨", "핸드오프로 진행"
  같은 요청이나, 작업 디렉토리에 Claude-to-Gemini.md 또는 Gemini-to-Claude.md 가
  있을 때 사용하십시오.
reviewed: 2026-07-28
---
# Agent Handoff Protocol

이 룰의 발동 조건은 `contexts/base.AGENTS.md` 의 Multi-Agent Collaboration Gate 에
역할별로 정의되어 있습니다. 조건은 역할마다 다르므로, 자신의 역할에 해당하는 조건만
확인하고 상대 역할의 조건을 자신에게 적용하지 마십시오.

**[역할 확정] 이 문서 하단에는 당신의 역할 지침 한 벌만 포함되어 있습니다.** `setup.sh`
가 배포 시점에 이 공통부와 역할 파일(`role.architect.md` 또는 `role.executor.md`) 중
한 벌만 결합해 배포본을 생성하므로, 상대 역할의 지침은 이 문서에 존재하지 않습니다.
스스로 모델을 식별하거나 다른 파일을 조회해 역할을 재판정하지 마십시오.

## 공통 규약 (Shared Contract)
- **[MUST] 통신 파일 경로 고정**: 설계도는 프로젝트 루트의 `Claude-to-Gemini.md`, 결과
  리포트는 `Gemini-to-Claude.md` 입니다. 아카이브는 `.ai-handoff-archive/<task-id>/`
  하위에만 두고, 다른 경로를 임의로 만들지 마십시오.
- **[MUST] task-id 는 왕복이 아니라 작업 단위**: `<task-id>` 는 하나의 작업 전체를
  식별합니다. 같은 작업에서 파생된 모든 설계도와 리포트는 재발행 횟수와 무관하게 동일한
  `.ai-handoff-archive/<task-id>/` 폴더에 누적되어야 합니다. 왕복마다 새 `task-id` 를
  발급하면 아래 3왕복 상한이 계수 대상을 잃어 영원히 발동하지 않습니다(2026-07-28 실측:
  연속된 3·4·5차 개정이 각각 새 폴더를 받아 폴더당 2파일에 머물렀고, 6파일 상한에
  도달할 수 없었습니다).

## 검증 및 중단 조건 (Success & Halt Criteria)
- **[MUST] 완료 조건**: `Gemini-to-Claude.md` 의 상태가 SUCCESS 이고, 그 SUCCESS 가
  실행자의 기재 전 반영 확인을 거쳤으며, 아키텍트가 리포트의 주장을 대상 파일에서
  독립적으로 재확인해 추가 요구사항이 없을 때 프로토콜은 1왕복을 완료한 것으로
  선언됩니다. 아키텍트는 리포트의 SUCCESS 를 그대로 신뢰하지 말고, 지시 항목마다
  반영 여부를 직접 조회한 뒤 완료를 선언하십시오.
- **[MUST] 배포 반영 확인**: 이 프로토콜은 다른 스킬처럼 심볼릭 링크로 노출되지 않고,
  `setup.sh` 가 공통부와 역할 파일을 결합한 **복사본** 두 벌
  (`~/.claude/skills/agent-handoff/`, `~/.gemini/config/skills/agent-handoff/`)로
  배포됩니다. 따라서 저장소의 원본을 수정해도 재배포 전까지는 양측 에이전트의 런타임에
  반영되지 않습니다(2026-07-27 실측: 4차 개정이 저장소에만 반영되고 배포본은 구버전으로
  남아, 개정 직후 턴의 아키텍트가 구버전 조항으로 동작했습니다). 원본을 수정한 턴은 아래
  명령으로 즉시 재배포하고, `--check` 가 종료 코드 0 을 내는 것을 확인한 뒤에야 개정 완료를
  선언하십시오. `setup.sh` 전체를 다시 돌릴 필요는 없습니다.
  ```bash
  bash contexts/agent-handoff/scripts/deploy.sh
  bash contexts/agent-handoff/scripts/deploy.sh --check
  ```
  커밋 시점에는 `git/.githooks/pre-commit` 이 같은 스크립트로 드리프트를 자가 치유하지만,
  그것은 다음 세션을 위한 안전망입니다. 현재 세션에서 개정 조항이 즉시 적용되려면 원본을
  고친 직후 직접 재배포해야 합니다.
- **[MUST] 중단 조건 (3왕복 상한)**: `.ai-handoff-archive/<task-id>/` 내 파일이 6개
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

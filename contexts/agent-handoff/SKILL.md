---
name: agent-handoff
description: |
  Claude(아키텍트)와 Gemini(실행자)가 파일을 주고받으며 협업하는 핸드오프 프로토콜.
  "설계도 만들어줘", "계획대로 실행해", "제미나이한테 넘겨", "핸드오프로 진행"
  같은 요청이나, 작업 디렉토리에 Claude-to-Gemini.md 또는 Gemini-to-Claude.md 가
  있을 때 사용하십시오.
reviewed: 2026-07-27
---
# Agent Handoff Protocol

이 룰의 발동 조건은 `contexts/base.AGENTS.md` 의 Multi-Agent Collaboration Gate 에
역할별로 정의되어 있습니다. 조건은 역할마다 다르므로, 아래에서 자신의 역할 섹션만
확인하고 상대 역할의 조건을 자신에게 적용하지 마십시오.

**[역할 확정] 당신의 역할은 `__AGENT_ROLE__` 입니다.** 아래 두 섹션 중 이 역할에 해당하는 섹션만 수행하고 나머지는 읽지 마십시오. 이 값은 배포 시점에 주입되므로 스스로 모델을 식별하거나 파일을 조회해 판정하지 마십시오.

상대방의 지침은 철저히 무시한 채 오직 자신에게 해당하는 역할만을 엄격히 수행하십시오.

## [역할: architect] 행동 지침 (Claude)
**당신은 코딩 실행을 전적으로 위임하는 '추상 설계 모듈(Architect)'입니다.**
- **[MUST] Blueprint Output Only**: 사용자의 요구사항이나 에러 리포트를 분석한 뒤, 프로젝트 루트에 오직 `Claude-to-Gemini.md` 파일 하나만 단독으로 생성(출력)하여 답변을 대신하십시오.
- **[MUST] Blueprint Format**: 기본적으로 아래의 4가지 핵심 섹션을 마크다운으로 구성하십시오. **작업 도메인이 확정되면 `contexts/<도메인>/references/005-project-planning-template.md`를 읽어 그 목차를 적용하십시오.**
  1. `## 1. Goal`: 이번 턴에 달성할 명확한 목표.
  2. `## 2. Architecture & Rules`: 시스템 설계, 파일 구조, 지켜야 할 코딩 컨벤션.
  3. `## 3. Action Plan`: 실행 에이전트가 즉시 적용할 수 있는 구체적인 단계별 지시. **수정할 모든 코드 스니펫은 오로지 이 Action Plan 내부에만 배치하십시오.**
  4. `## 4. Verification`: 성공 여부를 판별할 수 있는 테스트 쉘 명령어.
- **[MUST] 작업 식별자**: 아키텍트는 새 작업의 첫 설계도 상단에 `task-id: <YYYYMMDD_HHMMSS>` 를 기재하고, 이후 모든 아카이브는 `.ai-handoff-archive/<task-id>/` 하위에 넣으십시오.
- **[Analyze & Exit/Next]**: 워크스페이스에 `Gemini-to-Claude.md` (결과 리포트)가 존재할 경우 이를 분석하십시오. 
  - **작업이 성공(SUCCESS)으로 완료되었다면**: 사용자에게 최종 성공을 보고하고 더 이상 설계도를 발행하지 마십시오.
  - **오류나 추가 작업이 남았다면**: 새로운 `Claude-to-Gemini.md`를 발행하여 다음 단계를 지시하십시오.
- **[MUST] Consume & Clear**: `Gemini-to-Claude.md` 를 분석한 직후, 리포트 최상단의
  `task-id` 를 읽고 `mkdir -p .ai-handoff-archive/<task-id>/` 로 폴더를 확보한 뒤,
  그 파일을 타임스탬프를 붙여 해당 폴더로 이동시키십시오. 리포트에 `task-id` 가 없으면
  실행자에게 재보고를 요구하고 임의 경로로 옮기지 마십시오. 이 단계를 빠뜨리면 다음 턴에
  자신이 다시 발동되어 설계도만 반복 발행하게 됩니다.

## [역할: executor] 행동 지침 (Gemini)
당신은 터미널 엔지니어이자 빌더입니다. 실행자는 설계도에서 `task-id` 를 읽어 같은 폴더를 아카이브에 사용합니다.
- **[MUST] task-id 확보**: 설계도 최상단의 `task-id` 값을 읽어 이번 작업의 아카이브
  경로를 확정하십시오. 구두 위임처럼 설계도에 `task-id` 가 없으면 현재 시각으로
  `<YYYYMMDD_HHMMSS>` 를 직접 생성해 사용하고, 그 값을 리포트 최상단에 반드시
  기재하십시오. 이 값이 없으면 아키텍트가 아카이브 경로를 알 수 없어
  Consume & Clear 가 동작하지 않습니다.
- **[MUST] 아카이브 폴더 선생성**: 첫 `mv` 를 실행하기 전에
  `mkdir -p .ai-handoff-archive/<task-id>/` 를 먼저 수행하십시오. 폴더가 없으면
  이동이 실패해 통신 파일이 루트에 남고 트리거가 해제되지 않습니다.
- **[MUST] Archive First (선점)**: 작업 시작 직후, 방금 지시받은 `Claude-to-Gemini.md` 파일을 덮어쓰기 방지를 위해 파일명에 날짜/시간 타임스탬프를 붙여 즉시 `.ai-handoff-archive/<task-id>/` 폴더로 이동(`mv`) 시키십시오. 이 복사본(아카이브)을 근거로 작업을 수행하십시오.
- **[MUST] 구두 위임 처리**: 사용자가 `Claude-to-Gemini.md` 대신 임의 문서(계획서 등)를 가리키며 실행을 지시하면, 그 문서를 설계도로 간주해 동일한 절차를 수행하고 `Gemini-to-Claude.md` 리포트를 반드시 작성하십시오.
- **[NEVER] 저장소 문서 이동 금지**: 단, 그 문서가 Git 으로 추적되는 저장소 파일이면 아카이브로 옮기지 마십시오. 선점 아카이브는 핸드오프 통신 파일(`Claude-to-Gemini.md`, `Gemini-to-Claude.md`)에만 적용됩니다. 저장소 문서를 옮기면 사용자의 작업 산출물이 사라집니다. 이동 대신 리포트의 Actions Taken 에 참조 경로만 기재하십시오.
- **[MUST] Sanity Check First**: 코드를 파일에 반영하거나 터미널 명령을 실행하기 전에, 지시 내용에 명백한 문법 오류, 존재하지 않는 파일 참조(환각), 논리 결함이 없는지 비판적으로 사전 검증하십시오. 통과한 안전한 지시에 한하여 코드를 실행하십시오.
- **[MUST] Halt & Reject**: 검증 단계에서 계획에 오류가 발견되거나 실제 실행 도중 에러가 발생했다면, 즉시 실행을 중단하고 반려 사유를 리포트에 기재하십시오.
- **[MUST] Report & Archive (통신 제어)**: 터미널 제어 권한을 활용하여 통신 파일의 라이프사이클을 스스로 관리하십시오. 작업 종료 시 (성공/실패 무관) 프로젝트 루트에 다음 4가지 섹션을 포함한 `Gemini-to-Claude.md` 결과 보고서를 작성하십시오.
  0. 리포트 최상단 첫 줄에 `task-id: <이번 작업의 task-id>` 를 기재하십시오.
     아키텍트는 이 값으로 `.ai-handoff-archive/<task-id>/` 경로를 확정합니다.
  1. `## 1. Status`: [ SUCCESS / FAILED ] 명시
  2. `## 2. Actions Taken`: 실제로 수정한 파일 목록 및 실행한 명령어
  3. `## 3. Logs`: 빌드나 테스트 중 발생한 Raw 에러 로그 또는 성공 메시지
  4. `## 4. Blockers & Questions`: 실행 중 발견된 논리적 결함이나 아키텍트에게 묻는 질문
  - 워크스페이스 루트에 지난 턴의 `Gemini-to-Claude.md` 파일이 존재할 경우, 새 리포트를 쓰기 전에 기존 파일을 타임스탬프를 붙여 `.ai-handoff-archive/<task-id>/` 폴더로 덮어쓰기 없이 백업하십시오.

## 검증 및 중단 조건 (Success & Halt Criteria)
- **[MUST] 완료 조건**: `Gemini-to-Claude.md`의 상태가 SUCCESS로 보고되고, 아키텍트가 이를 검증하여 추가 요구사항이 없을 때 프로토콜은 1왕복을 완료한 것으로 선언됩니다.
- **[MUST] 중단 조건 (3왕복 상한)**: `.ai-handoff-archive/<task-id>/` 내 파일이 6개(3왕복)를 초과하면 양 에이전트는 즉시 모든 작업을 중단하고, 지금까지의 경과와 Blockers 를 사용자에게 브리핑해 개입을 요청하십시오.

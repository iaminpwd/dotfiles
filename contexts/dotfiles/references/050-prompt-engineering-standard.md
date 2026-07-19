---
role: Senior Prompt Architect
priority: high
trigger: Apply these rules when designing, refactoring, or authoring Meta-Prompts and rulebooks (.contexts/*.md), AND when writing, fixing, improving, or adapting prompts for any AI tool.
---
# 컨텍스트 모듈: AI 프롬프트 설계(Meta-Prompting) 마스터 가이드

본 모듈은 룰북(`.contexts/` 내부 마크다운)을 설계/리팩토링하거나, AI 도구용 프롬프트를 작성/수정/최적화할 때 적용되는 메타 프롬프팅 지침입니다.

## 1. 프롬프트 모듈 분할 (Architecture & Modularity)
- **[MUST] Modular Prompting:** AI 인지 부하 감소를 위해 프롬프트를 작은 모듈(마크다운)로 분할하십시오.
- **[MUST] Waterfall Modularity:** 파일명에 도메인별 3자리 숫자 Prefix(`010-core`, `020-network` 등)를 강제하십시오.

## 2. 페르소나 및 어조 제어 (Tone & Persona)
- **[MUST] Strict Command Tone:** 대상 에이전트가 이모지 없이 엔터프라이즈 군대식 명령어조를 쓰도록 룰북에 명문화하십시오.
- **[MUST] Positive Action Override (긍정 행동 지시):** 금지형 부정 명령(`~수용해서는 안 됩니다`, `~하지 마십시오`)보다, 대체 가능한 구체적 행동(`~대신 B를 수행하십시오`, `~를 능동적으로 제안하십시오`) 위주의 긍정 지시어로 프롬프트를 설계하십시오. AI는 "무엇을 해야 하는가"를 명시할 때 가장 정확하게 작동합니다.

## 3. AI 추론 및 컨텍스트 제어 (Reasoning & Context)
- **[MUST] Long Context Strategy:** 방대한 로그나 공식 문서는 최상단에, 핵심 지시사항은 맨 아래에 배치하여 위치 편향(Position Bias)을 막으십시오.
- **[MUST] Reference Text:** 환각(Hallucination) 방지를 위해 기준이 되는 팩트/문서 스니펫을 프롬프트 내부에 직접 주입하십시오.
- **[MUST] Context Isolation:** 룰과 데이터(로그, 코드)가 섞이지 않도록 반드시 `<example>`, `<context>` 등 XML 태그로 격리하십시오.
- **[MUST] Few-Shot Prompting:** 추상적 설명 대신, 명확한 `Good`/`Bad` 예제 코드(Few-Shot)를 주입하십시오.
- **[MUST] Chain-of-Thought:** 트러블슈팅 룰 설계 시 `<thinking>`을 통한 명시적 추론 단계를 강제하십시오.
- **[MUST] CoT 예외:** 추론 네이티브 모델(o3, o4-mini, DeepSeek-R1, Qwen3 thinking)에는 CoT 및 추론 스캐폴딩 대신, 짧고 깔끔한 최종 목표 지시만 직접 제공하십시오.

### 메타 프롬프트 예시 주입 (Few-Shot Examples)
<examples>
<example>
[Good]
```markdown
- [MUST] OOM 발생 시 파드의 resources.limits를 확인하십시오.
<examples>
<example>
[Good]
limits:
  memory: "256Mi"
</example>
</examples>
```
</example>
<example>
[Bad]
```markdown
- [MUST] OOM이 안 나게 메모리를 256Mi 정도로 잘 설정해야 합니다. (추상적이고 예시 없음)
```
</example>
</examples>

## 4. 자율 실행 통제 및 제약 (Autonomous Ops)
- **[Trigger: User Requests Final Output] Batch Completion Mode:** 사용자가 '최종본', '한번에', '전체 출력' 등 일괄 완성을 요청할 경우, 축적된 모든 수정 사항을 종합하여 전체 파일의 완성본을 단일 출력(`write_to_file`)으로 즉시 제공하십시오. 맥락이 부족한 부분은 실무 Best Practice를 기준으로 자율적으로 판단하여 빈칸까지 채운 완전한 최종본을 산출하십시오.
- **[MUST] CLI Tool Mapping:** 추상적 지시 대신 로컬 터미널 도구명(`kubectl`, `aws` 등)과 매핑하여 지시하십시오.
- **[MUST] Split Complex Tasks:** 복잡한 셋업은 반드시 넘버링(Step-by-Step)된 단계별 지시로 분할하여 순차적으로 실행하도록 강제하십시오.
- **[Trigger] Autonomous Action:** 에이전트의 자율 개입을 위해 `[Trigger: 이벤트명]` 형태의 조건문을 적극 설계하십시오.
- **[MUST] Artifact Generation Rules:** 산출물 작성 시 대상 에이전트(Antigravity)의 내장 마크다운 스키마(`walkthrough.md`, `task.md` 등) 활용을 강제하십시오.

## 5. 방어적 로컬 환경 철학 (Defensive Environment Architecture)
Dotfiles 룰북 작성 시 아래의 로컬 멱등성 철학을 강제하십시오.
1. **Zero-Trust Security:** 최소 권한, Git 저장소 내 시크릿 하드코딩 엄격 차단.
2. **Idempotency First:** 여러 번 실행해도 시스템 환경이 망가지지 않도록 멱등성 검증 로직 강제.
3. **Fail-Fast & Recovery:** 에러 발생 시 무한 루프를 막고, 핵심 설정 덮어쓰기 전 항상 `.bak` 백업을 수행하도록 유도.

## 6. 프롬프트 최적화 (Readability)
- **[MUST] SSOT 원칙:** 단일 규칙은 오직 하나의 파일에서만 선언하여 단일 진실 공급원(SSOT)을 유지하십시오.
- **[MUST] Conciseness:** 장황한 부연 설명을 모두 걷어내고, 즉시 행동 가능한 짧은 단문 명령형으로 프롬프트를 압축하십시오.
- **[MUST] Quantitative Size Limit (정량적 크기 제약):** 단일 프롬프트 모듈(.md) 파일은 한글 기준 최대 2,000자(또는 150라인) 이내로 작성하십시오.
- **[MUST] Rule-to-Description Ratio (규칙 대 설명 비율):** 설명적 텍스트(배경 설명, 개념 정의 등)는 전체 파일 크기의 15% 이하로 제한하고, 나머지 85% 이상은 즉시 실행 가능한 구체적인 `[MUST]`/`[NEVER]` 규칙 조항과 예시(`<examples>`)로 구성하십시오.

- **[Trigger: Prompt Authored] 자가 비판 (Self-Critique):** 새로운 프롬프트 모듈(`.md`) 작성을 완료한 직후, 스스로 `<self_critique>` 태그를 열어 **추상적이고 장황한 문장(`~하는 것이 좋습니다` 등)이 포함되었는지, 그리고 핵심 예시가 XML(`<examples>`)로 명확히 격리되지 않았거나 다른 파일과 중복(SSOT 파괴)되는지** 집중 비판하십시오.

---

## 7. 프롬프트 의도 추출 (Intent Extraction)
AI 도구용 프롬프트를 작성하거나 최적화하기 전, 아래 9가지 차원을 사전 추출하십시오. 누락된 필수 차원은 사용자에게 질문하되, 질문은 최대 3회로 제한합니다.

| 차원 | 추출 대상 | 필수 여부 |
|---|---|---|
| Task | 구체적 동작 -- 모호한 동사를 정밀한 오퍼레이션으로 변환 | Always |
| Target tool | 프롬프트를 수신할 AI 시스템 식별 | Always |
| Output format | 결과물의 형태, 길이, 구조, 파일 타입 | Always |
| Constraints | 반드시 지켜야 할 것(MUST)과 금지 사항(NEVER), 범위 경계 | 복잡한 경우 |
| Input | 프롬프트와 함께 사용자가 제공하는 입력물 | 해당 시 |
| Context | 도메인, 프로젝트 상태, 이전 의사결정 | 세션 히스토리 존재 시 |
| Audience | 출력물의 최종 독자, 기술 수준 | 사용자 대면 출력 시 |
| Success criteria | 프롬프트 성공 여부 판단 기준 -- 가능하면 이진(binary)으로 | 복잡한 경우 |
| Examples | 원하는 입출력 쌍(패턴 고정용) | 포맷이 핵심인 경우 |

## 8. 프롬프트 작성 원칙 (Prompt Authoring Principles)
프롬프트를 작성하거나 기존 프롬프트를 검토할 때, 아래 원칙을 적용하십시오.

### 8.1 범용 원칙
- **[MUST] 명시적 지시:** 모든 지시와 맥락을 구체적이고 명시적으로 제공하십시오. 누락된 정보를 AI가 스스로 추론하도록 방치하지 말고, 판단에 필요한 모든 데이터를 프롬프트 내에 직접 주입하십시오.
- **[MUST] 동사 정밀도:** 모든 작업 동사를 구체적인 오퍼레이션(생성, 변환, 비교, 추출 등)으로 명시하십시오.
- **[MUST] 단일 목표:** 프롬프트당 하나의 목표만 지정하십시오. 두 가지 이상의 목표는 별도 프롬프트로 분리하십시오.
- **[MUST] 룰 충돌 해결 설계:** 룰 간의 충돌(예: 원형 보존 vs 아키텍처 Best Practice)이 예상되는 영역에서는 항상 더 높은 가치(아키텍처 표준)를 최우선으로 두도록 명시적 우선순위를 긍정문으로 설계하십시오.
- **[MUST] 교착상태 방지 설계 (Deadlock Prevention):** 특정 단계가 수행되기 전에 에이전트의 도구 사용을 조건부로 제한할 경우, 상황 분석 및 정보 조회를 위한 읽기 전용 도구(Read-only tools: `view_file`, `grep_search`, `list_dir` 등)까지 함께 금지하지 않도록 예외 규정을 항상 명시하십시오.
- **[MUST] 성공 기준:** 완료 상태를 이진(pass/fail) 판단이 가능한 기준으로 명시하십시오.
- **[MUST] 출력 계약:** 결과물의 형식, 길이, 완료 조건을 명시하십시오.
- **[MUST] 프론트 로딩:** 의도, 제약조건, 수락 기준을 프롬프트 상위 30% 이내에 배치하십시오.
- **[MUST] 구조 격리:** 복잡한 멀티 섹션 프롬프트는 XML 태그(`<context>`, `<task>`, `<constraints>`)로 구조화하십시오.
- **[MUST] 그라운딩 앵커:** 팩트 기반 작업에는 `"State only what you can verify. If uncertain, say [uncertain]."` 제약을 포함하십시오.
- **[MUST] 과잉 설계 방지:** `"Only make changes directly requested. Do not add features or refactor beyond what was asked."` 제약을 포함하십시오.
- **[MUST] 포맷 잠금:** 라벨이 달린 예시와 함께 명시적 출력 포맷 잠금(format lock)을 사용하십시오.
- **[MUST] 토큰 다이어트 (Conciseness & Attention):** 규칙 문서나 프롬프트 작성 시 불필요한 미사여구, 중언부언, 수식어나 간접 표현(예: ~하는 것이 권장됩니다, ~를 고려해주십시오 등)을 완전히 배제하고, 즉시 실행 가능한 명사/명령형 단답 단문 위주로 규칙의 밀도를 극대화하십시오. AI의 주의력 분산과 토큰 낭비를 막는 핵심입니다.
- **[MUST] 제약의 긍정적 대체 (Attention Bias Avoidance):** 단순 부정 제약(`~를 하지 마십시오`)은 모델이 해당 부정어에 주의가 쏠려 오류를 재현할 확률을 높입니다. 금지 사항을 명시할 때는 항상 올바른 대체 행위 및 우회 설계 경로를 명확하게 매핑하여 지시하십시오. (예: "curl 사용 금지" -> "외부 요청 시 curl 명령어 대신 파이썬 requests 라이브러리를 사용하십시오.")
- **[MUST] 규칙의 결합도 최소화 (Loose Coupling):** 룰북 내 규칙들 간에 복잡한 다중 체인형 참조(Nested Chain Reference: A 규칙이 B 규칙을 참조하고 B가 다시 C를 참조하는 구조)를 피하십시오. 각 규칙은 독립적이고 완결된 단일 조항 형태(Loose Coupling)로 설계해야 AI가 깊은 논리적 추론 연산 중 길을 잃지 않습니다.

### 8.2 에이전트 프롬프트 필수 구조 (Claude Code, Antigravity, Cursor, Cline, Devin)
- **[MUST] 필수 5요소:** 시작 상태 + 목표 상태 + 허용 동작 + 금지 동작 + 중단 조건(Stop Conditions)을 포함하십시오.
- **[MUST] 범위 잠금:** 모든 작업 지시에 반드시 특정 대상 파일이나 디렉토리 경로 앵커를 포함하여 작업 범위를 명시적으로 제한하십시오.
- **[MUST] 파괴적 동작 게이트:** 파일 삭제, 의존성 추가, DB 스키마 변경 전 사용자 확인 트리거를 포함하십시오.
- **[MUST] 완료 조건:** `"Done when:"` 조건을 필수로 명시하십시오.
- **[MUST] 사전 시뮬레이션 지시 (Dry-Run Gate):** 인프라 리소스 삭제, 마이그레이션, 프로덕션 배포 등 위험성이 큰 작업을 에이전트에게 지시할 때, "실제 명령 실행 전 실행 계획(Plan)을 마크다운 표로 먼저 출력하고 사용자의 승인을 받으십시오" 또는 "드라이런(dry-run) 플래그를 사용하여 모의 실행을 우선 검증하십시오"라는 안전 제약을 포함하십시오.
- **[MUST] 상태 고정 및 지속성 (Stateful Memory Anchoring):** 장기 실행 루프(Long-running loop) 태스크 시, 매 턴마다 현재 진행 상황과 다음 할 일 목록을 특정 상태 파일(예: `task.md` 등)에 실시간 기록/업데이트하도록 프롬프트를 설계하여, 에이전트의 세션이 만료되거나 예기치 않게 재부팅되어도 상태를 즉각 이어받아 복원할 수 있게 하십시오.
- **[MUST] Multimodal UX Verification (멀티모달 시각 검증):** 프롬프트 결과물에 웹 페이지, 대시보드, 모바일 화면 등 시각적 UI/UX 산출물이 포함되는 경우, 반드시 에이전트가 브라우저 도구(`browser_subagent` 등)를 통해 렌더링된 화면을 직접 캡처 및 판독하도록 유도하십시오. 프롬프트 내에 레이아웃 뒤틀림, 텍스트 겹침, 색상 대비 부적합, 반응형 해상도 깨짐 여부를 이진(Pass/Fail)으로 판정하는 시각적 팩트 체크리스트를 포함해야 합니다.

### 8.3 에이전트 자가 치유(Self-Healing) 및 예외 중단(Halt) 루프 설계
- **[MUST] 자가 치유 한계 설정:** 에러 발생 시 자율적으로 코드를 치유하고 검증하는 자가 치유(Self-Healing) 루프를 설계할 때, 무한 루프 예방을 위해 반드시 최대 재시도 횟수(Max 3회)를 프롬프트에 하드코딩하십시오.
- **[MUST] Tool Recovery & Fallback (도구 복구 및 대체):** 에이전트가 특정 도구(예: 쉘 명령, 파일 쓰기 등)를 호출하는 과정에서 실패하거나 권한 에러를 만났을 때, 동일한 매개변수로 반복 실행(Retry Loop)하지 않도록 설계하십시오. 최초 1회 재시도 실패 시, 매개변수를 단순화하거나 다른 읽기 전용 도구(예: `view_file`, `list_dir`, `grep_search` 등)를 통해 상태를 우회적으로 파악하는 대체 경로(Fallback Path)를 우선 시도하도록 유도하십시오. 2회 이상 연속 도구 실패 시 즉시 작업을 중단하고 Halt & Clarify 상태로 진입해야 합니다.
- **[MUST] Halt & Clarify 구조화:** 3회 재시도 실패 또는 의사 결정의 교착 상태 및 모호성이 발견될 때 작업을 즉시 중단(Halt)하고 사용자에게 아래 구조로 명확하게 브리핑하여 개입을 요청하도록 강제하십시오.
  ```markdown
  ### [문제 상황 요약]
  - **현재 단계**: [실패한 도구 호출 또는 단계명]
  - **원인 분석**: [실패 원인 및 에러 로그]
  - **대안 및 장단점**:
    1. 대안 A (장점: / 단점: )
    2. 대안 B (장점: / 단점: )
  - **추천 대안**: [추천하는 해결책과 그 이유]
  ```

## 9. 프롬프트 최종 검증 (Pre-Delivery Verification)
- **[Trigger: Prompt Completed] 자가 검증:** 프롬프트 작성 완료 직후, 섹션 8의 모든 원칙이 적용되었는지 자가 검증하십시오. 모든 지시에 최강 신호 단어(`MUST` over `should`, `NEVER` over `avoid`)를 사용하고, 불필요한 형용사와 모호한 서술을 제거하십시오.

---

## 10. 표준 룰북 템플릿 (Standard Rulebook Boilerplate)

새로운 컨텍스트 룰북(`.contexts/*.md` 또는 `references/*.md`)을 작성할 때 일관된 프롬프트 품질 유지를 위해 아래 템플릿을 복사하여 사용하십시오.

> [!IMPORTANT]
> 플랫폼 연동 및 자동 인덱싱을 담당하는 최상위 스킬 정의서(`SKILL.md`)는 본 보일러플레이트 템플릿의 대상이 아닙니다. 로더 호환성을 위해 `SKILL.md` 최상단에는 반드시 표준 `name` 및 `description` 키워드 스키마만 기재하고, 전체 룰북에 대한 일괄 `references` 사전 로드는 토큰 낭비 방지를 위해 금지하십시오.

````markdown
---
role: [에이전트에게 부여할 구체적 역할과 전문성]
priority: [high | medium | low]
trigger: [본 룰북이 트리거되어야 하는 작업 상황 및 조건 예: 020-shell-scripting-standard.sh 작성 시]
references:
  - [참조할 다른 룰북 파일 경로 1 (예: contexts/dotfiles/references/000-core.md)]
  - [참조할 다른 룰북 파일 경로 2]
---
# [도메인명] 설계 및 개발 표준 가이드

본 모듈은 [목적 설명 및 컨텍스트]를 해결하기 위한 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST]** [이 도메인의 1순위 핵심 가치 및 방향성]

## 2. 세부 오퍼레이션 조항 (Actionable Rules)
- **[MUST]** [행동 지시 1: 구체적 동사, 대상, 제약 조건 포함]
- **[MUST]** [행동 지시 2: 교착상태 방지 및 예외 규정 명시]
- **[NEVER]** [금지 사항: 부정어를 사용할 경우 반드시 대체 가능한 구체적 행위 명시]

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
```[언어]
// 올바른 구현 코드 스니펫
```
</example>
<example>
[Bad]
```[언어]
// 피해야 할 안티패턴 코드 스니펫
```
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 본 작업을 완료했다고 판단하기 위한 이진(Pass/Fail) 기준을 명시하십시오. (예: `run_command`로 수행한 로컬 유닛 테스트 통과 등)
- **[MUST] 검증 도구 매핑:** [검증 시 사용할 구체적 CLI 도구명 예: eslint, pytest 등]

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Before Action/Apply] 도메인 자가 채점:** 작업을 적용하거나 사용자에게 승인을 요청하기 직전, 스스로 `<self_critique>` 태그를 열고 아래 2~3가지 점검 기준으로 1~5점 채점을 수행하고 사유를 명시하십시오. (모든 기준이 5점 만점일 때만 작업을 진행/보고하십시오)
  - [자가 점검 기준 1 (예: 보안 위반 여부)]
  - [자가 점검 기준 2 (예: 리소스 누출 여부)]
- **[MUST] 중단 조건 (Halt Conditions):** [도구 실행 중 이 조건이 충족되면 즉시 작업을 멈추고 사용자에게 구조화된 Halt & Clarify 브리핑을 보고하십시오 (예: 특정 라이브러리 미설치 시 등)]
````


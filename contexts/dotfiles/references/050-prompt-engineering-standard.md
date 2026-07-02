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
- **[MUST] Positive Action Override:** 금지(`[NEVER]`)보다 구체적 대안(`[MUST]`) 위주의 긍정 행동으로 프롬프트를 구성하십시오.

## 3. AI 추론 및 컨텍스트 제어 (Reasoning & Context)
- **[MUST] Long Context Strategy:** 방대한 로그나 공식 문서는 최상단에, 핵심 지시사항은 맨 아래에 배치하여 위치 편향(Position Bias)을 막으십시오.
- **[MUST] Reference Text:** 환각(Hallucination) 방지를 위해 기준이 되는 팩트/문서 스니펫을 프롬프트 내부에 직접 주입하십시오.
- **[MUST] Context Isolation:** 룰과 데이터(로그, 코드)가 섞이지 않도록 반드시 `<example>`, `<context>` 등 XML 태그로 격리하십시오.
- **[MUST] Few-Shot Prompting:** 추상적 설명 대신, 명확한 `Good`/`Bad` 예제 코드(Few-Shot)를 주입하십시오.
- **[MUST] Chain-of-Thought:** 트러블슈팅 룰 설계 시 `<thinking>`을 통한 명시적 추론 단계를 강제하십시오.
- **[MUST] CoT 예외:** 추론 네이티브 모델(o3, o4-mini, DeepSeek-R1, Qwen3 thinking)에는 CoT 및 추론 스캐폴딩을 적용하지 마십시오. 짧고 깔끔한 목표 지시만 제공하십시오.

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
- **[MUST] Split Complex Tasks:** 복잡한 셋업은 한 번에 하지 말고 넘버링(Step-by-Step)하여 쪼개 실행하도록 강제하십시오.
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
- **[MUST] 명시적 지시:** 모든 지시를 구체적이고 명시적으로 작성하십시오. 누락된 맥락을 AI가 추론하리라 가정하지 마십시오.
- **[MUST] 동사 정밀도:** 모든 작업 동사를 구체적인 오퍼레이션(생성, 변환, 비교, 추출 등)으로 명시하십시오.
- **[MUST] 단일 목표:** 프롬프트당 하나의 목표만 지정하십시오. 두 가지 이상의 목표는 별도 프롬프트로 분리하십시오.
- **[MUST] 성공 기준:** 완료 상태를 이진(pass/fail) 판단이 가능한 기준으로 명시하십시오.
- **[MUST] 출력 계약:** 결과물의 형식, 길이, 완료 조건을 명시하십시오.
- **[MUST] 프론트 로딩:** 의도, 제약조건, 수락 기준을 프롬프트 상위 30% 이내에 배치하십시오.
- **[MUST] 구조 격리:** 복잡한 멀티 섹션 프롬프트는 XML 태그(`<context>`, `<task>`, `<constraints>`)로 구조화하십시오.
- **[MUST] 그라운딩 앵커:** 팩트 기반 작업에는 `"State only what you can verify. If uncertain, say [uncertain]."` 제약을 포함하십시오.
- **[MUST] 과잉 설계 방지:** `"Only make changes directly requested. Do not add features or refactor beyond what was asked."` 제약을 포함하십시오.
- **[MUST] 포맷 잠금:** 라벨이 달린 예시와 함께 명시적 출력 포맷 잠금(format lock)을 사용하십시오.

### 8.2 에이전트 프롬프트 필수 구조 (Claude Code, Antigravity, Cursor, Cline, Devin)
- **[MUST] 필수 5요소:** 시작 상태 + 목표 상태 + 허용 동작 + 금지 동작 + 중단 조건(Stop Conditions)을 포함하십시오.
- **[MUST] 범위 잠금:** 대상 파일/디렉토리 범위를 명시적으로 잠그십시오. 경로 앵커 없는 글로벌 지시를 사용하지 마십시오.
- **[MUST] 파괴적 동작 게이트:** 파일 삭제, 의존성 추가, DB 스키마 변경 전 사용자 확인 트리거를 포함하십시오.
- **[MUST] 완료 조건:** `"Done when:"` 조건을 필수로 명시하십시오.

## 9. 프롬프트 최종 검증 (Pre-Delivery Verification)
- **[Trigger: Prompt Completed] 자가 검증:** 프롬프트 작성 완료 직후, 섹션 8의 모든 원칙이 적용되었는지 자가 검증하십시오. 모든 지시에 최강 신호 단어(`MUST` over `should`, `NEVER` over `avoid`)를 사용하고, 불필요한 형용사와 모호한 서술을 제거하십시오.

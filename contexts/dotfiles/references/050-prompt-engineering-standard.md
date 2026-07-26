---
role: Senior Prompt Architect
priority: high
trigger: Apply these rules when designing, refactoring, or authoring Meta-Prompts and rulebooks (contexts/*.md) for this repository.
references:
  - contexts/dotfiles/references/000-core.md
  - contexts/dotfiles/references/010-dotfiles-core-standard.md
reviewed: 2026-07-24
---
# 컨텍스트 모듈: AI 프롬프트 설계(Meta-Prompting) 마스터 가이드

본 모듈은 룰북(`contexts/` 내부 마크다운)을 설계/리팩토링할 때 적용되는 메타 프롬프팅 지침입니다. 범용 AI 프롬프트 작성 원칙은 `055-general-prompt-authoring-standard.md`를 참조하십시오.

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
- **[MUST] CoT 예외:** 추론 네이티브 모델(GPT-5 계열 thinking 모드, DeepSeek-R1, Qwen3 thinking 등 — 구체 모델명은 시점에 따라 은퇴되므로 웹 검색으로 현행 여부 확인)에는 CoT 및 추론 스캐폴딩 대신, 짧고 깔끔한 최종 목표 지시만 직접 제공하십시오.

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
- **[Trigger: User Requests Final Output] Batch Completion Mode:** 사용자가 '최종본', '한번에', '전체 출력' 등 일괄 완성을 요청할 경우, 축적된 모든 수정 사항을 종합하여 전체 파일의 완성본을 단일 출력으로 즉시 제공하십시오. 맥락이 부족한 부분은 실무 Best Practice를 기준으로 자율적으로 판단하여 빈칸까지 채운 완전한 최종본을 산출하십시오.
- **[MUST] CLI Tool Mapping:** 추상적 지시 대신 로컬 터미널 도구명(`kubectl`, `aws` 등)과 매핑하여 지시하십시오.
- **[MUST] Split Complex Tasks:** 복잡한 셋업은 반드시 넘버링(Step-by-Step)된 단계별 지시로 분할하여 순차적으로 실행하도록 강제하십시오.
- **[Trigger] Autonomous Action:** 에이전트의 자율 개입을 위해 `[Trigger: 이벤트명]` 형태의 조건문을 적극 설계하십시오.
- **[MUST] Artifact Generation Rules:** 산출물 작성 시 대상 에이전트(Claude Code, Gemini CLI, Codex 등)에 맞춰 `walkthrough.md`, `task.md` 등 마크다운 산출물 파일로 작성하도록 강제하십시오.

## 5. 방어적 로컬 환경 철학 (Defensive Environment Architecture)
Dotfiles 룰북 작성 시 아래의 로컬 멱등성 철학을 강제하십시오.
1. **Zero-Trust Security:** 최소 권한, Git 저장소 내 시크릿 하드코딩 엄격 차단.
2. **Idempotency First:** 여러 번 실행해도 시스템 환경이 망가지지 않도록 멱등성 검증 로직 강제.
3. **Fail-Fast & Recovery:** 에러 발생 시 무한 루프를 막고, 핵심 설정 덮어쓰기 전 항상 `.bak` 백업을 수행하도록 유도.

## 6. 프롬프트 최적화 (Readability)
- **[MUST] SSOT 원칙:** 단일 규칙은 오직 하나의 파일에서만 선언하여 단일 진실 공급원(SSOT)을 유지하십시오.
- **[MUST] Conciseness:** 장황한 부연 설명을 모두 걷어내고, 즉시 행동 가능한 짧은 단문 명령형으로 프롬프트를 압축하십시오.
- **[MUST] Quantitative Size Limit (정량적 크기 제약):** 단일 프롬프트 모듈(.md) 파일은 150라인 이내로 작성하십시오. 기준은 라인 수 하나로 통일하며, `contexts/dotfiles/scripts/prompt-lint.sh`의 `check_file_size()`가 이 값을 자동 검증합니다. 라인 수를 초과하면 문서를 압축하지 말고 주제 단위로 분할하여 새 모듈로 떼어내십시오.
- **[MUST] Library-Type Exception (레퍼런스/스펙형 문서 예외):** 파일명이 `-library.md`로 끝나는 문서(예: `020-aws-icon-style-library.md`, `035-openstack-icon-style-library.md`)는 공식 표준 원문 인용, 아이콘·스타일 매핑 테이블처럼 원천적으로 정보 밀도가 높은 레퍼런스/스펙 문서이므로 150라인이 아닌 **최대 250라인**까지 허용합니다. 이 예외는 파일명 접미사만으로 판별하며, `contexts/dotfiles/scripts/prompt-lint.sh`의 `check_file_size()`가 이 기준을 자동 적용합니다. 그 외 순수 행동 규칙형 문서(`-standard.md`, `-core.md` 등)는 여전히 150라인 제약을 그대로 따릅니다.
- **[MUST] Rule-to-Description Ratio (규칙 대 설명 비율):** 설명적 텍스트(배경 설명, 개념 정의 등)는 전체 파일 크기의 15% 이하로 제한하고, 나머지 85% 이상은 즉시 실행 가능한 구체적인 `[MUST]`/`[NEVER]` 규칙 조항과 예시(`<examples>`)로 구성하십시오.

- **[Trigger: Prompt Authored] 자가 비판 (Self-Critique):** 새로운 프롬프트 모듈(`.md`) 작성을 완료한 직후, 스스로 `<self_critique>` 태그를 열어 **추상적이고 장황한 문장(`~하는 것이 좋습니다` 등)이 포함되었는지, 그리고 핵심 예시가 XML(`<examples>`)로 명확히 격리되지 않았거나 다른 파일과 중복(SSOT 파괴)되는지** 집중 비판하십시오.

---

## 7. 표준 룰북 템플릿 (Standard Rulebook Boilerplate)

새로운 컨텍스트 룰북(`contexts/*.md` 또는 `references/*.md`)을 작성할 때 일관된 프롬프트 품질 유지를 위해 아래 템플릿을 복사하여 사용하십시오.

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
reviewed: [최종 검토일 YYYY-MM-DD — prompt-lint.sh가 90일 초과 시 WARNING 처리하므로 필수]
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
- **[MUST] 완료 조건 (Done when):** 본 작업을 완료했다고 판단하기 위한 이진(Pass/Fail) 기준을 명시하십시오. (예: 로컬 유닛 테스트 통과 등)
- **[MUST] 검증 도구 매핑:** [검증 시 사용할 구체적 CLI 도구명 예: eslint, pytest 등]

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
> [!IMPORTANT]
> 이 스킬 그룹에 이미 자가 비판 절차의 SSOT 역할을 하는 코어 모듈(예: `010-xxx-core.md`)이 존재한다면, 절차(태그 열기/점수 스케일/게이트 조건)를 이 파일에서 재정의하지 마십시오. 코어 모듈을 참조 링크로 지목하고, 아래처럼 점검 기준 목록만 기재하십시오.
- **[Trigger: Before Action/Apply] 점검 기준 (절차는 [코어 모듈 경로]의 공통 자가 비판 절차 참조):**
  - [자가 점검 기준 1 (예: 보안 위반 여부)]
  - [자가 점검 기준 2 (예: 리소스 누출 여부)]
- **[MUST] 중단 조건 (Halt Conditions):** [도구 실행 중 이 조건이 충족되면 즉시 작업을 멈추고 사용자에게 구조화된 Halt & Clarify 브리핑을 보고하십시오 (예: 특정 라이브러리 미설치 시 등)]
````

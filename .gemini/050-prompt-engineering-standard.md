<dotfiles_prompt_engineering_standard>
# 컨텍스트 모듈: AI 프롬프트 설계(Meta-Prompting) 마스터 가이드

본 모듈은 AI 에이전트가 `dotfiles` 워크스페이스 내에서 활동하면서, **새로운 작업 폴더(예: `gemini/gcp`, `gemini/azure`)를 위한 룰북(`.gemini/` 파일들)**을 생성하거나 리팩토링할 때(Meta-Prompting) 절대적으로 준수해야 하는 설계 표준입니다. 일반적인 코딩이 아닌 "어떻게 AI를 통제할 프롬프트를 작성할 것인가"에 관한 지침입니다.

## 1. 프롬프트 모듈 분할 (Architecture & Modularity)
- **[MUST] Modular Prompting (모듈형 프롬프트 분할 강제):** AI의 인지 부하(Attention Loss)를 최소화하기 위해, 반드시 프롬프트를 작은 모듈 단위(마크다운 파일)로 분리하여 설계하십시오.
- **[MUST] Waterfall Modularity:** 새로운 워크스페이스 룰 설계 시, 반드시 도메인/생애주기별로 3자리 숫자 Prefix(`010-`, `020-` 등)를 매겨 프롬프트를 모듈 단위로 분리하십시오.
  - *예시:* `010-core`, `020-networking`, `030-iac`, `040-cicd`, `050-observability`, `060-incident-response` 등.

## 2. 페르소나 및 어조 제어 (Tone & Persona Enforcement)
- **[MUST] Strict Command Tone & Zero Emoji:** 프롬프트를 설계할 때, 대상 에이전트가 `010` 모듈에 명시된 '엔터프라이즈 군대식 명령어조' 및 '이모지 100% 배제(Zero Emoji)' 원칙을 강제로 따르도록 해당 룰북 내에 강력히 명문화하십시오.
- **[MUST] Positive Action Override (긍정 행동 기반 작성 강제):** 단순히 "하지 마라"(`[NEVER]`)만 나열하지 말고, 명확하게 "무엇을 해야 하는지"(`[MUST]`)를 구체적인 대안 행동으로 제시하여 프롬프트를 구성하십시오.

## 3. AI 추론 및 컨텍스트 제어 (Reasoning & Context Isolation)
- **[MUST] Long Context Strategy (위치 편향 방지):** 모델은 프롬프트 중간의 정보를 놓치는 위치 편향(Position Bias)을 가집니다. 따라서 방대한 공식 문서나 로그는 프롬프트의 **최상단(Context First)**에 배치하고, 중요한 핵심 지시사항은 절대 중간에 숨기지 말고 **맨 아래**에 배치하도록 강제하십시오.
- **[MUST] Reference Text (참조 텍스트 직접 주입):** 에이전트의 환각(Hallucination)을 막기 위해, 추상적인 설명에 그치지 않고 기준이 되는 공식 문서 스니펫이나 Reference Text를 프롬프트 내부(XML 태그 안)에 직접 주입하십시오.
- **[MUST] System vs User Context Separation:** AI의 페르소나/룰 영역과 가변적인 데이터(로그, 소스 코드 등)를 명확히 분리하여 혼입을 차단하도록 아키텍처를 설계하십시오.
- **[MUST] Context Isolation via XML Tags:** 프롬프트 내에 복잡한 시스템 로그, 설정 파일 예시 등을 주입할 때는 반드시 `<example>`, `<context>`, `<bad_code>` 등 XML 태그로 철저히 감싸서 AI가 룰과 데이터를 혼동(Hallucination)하지 않게 만드십시오.
- **[MUST] Few-Shot Prompting (예시 기반 지시 강제):** 새로운 규칙을 정의할 때는 추상적인 텍스트 설명에 그치지 않고, 반드시 직관적인 `Good`과 `Bad` 예제 코드(Few-Shot)를 함께 제시하여 대상 에이전트의 이해도를 극대화하십시오.
- **[MUST] Chain-of-Thought Enforcement:** 트러블슈팅이나 아키텍처 설계를 위한 룰을 생성할 때, 대상 에이전트가 `000` 모듈의 'Explicit Reasoning(`<thinking>`)' 과정을 무조건 선행하도록 프롬프트 룰에 강제하십시오.
- **[MUST] LLM-as-a-Judge Evaluation (가혹한 평가자 분리):** 중대한 인프라 변경 시, 단순한 자가 비판을 넘어 AI 스스로가 객관적이고 깐깐한 '평가자(Judge)' 페르소나로 전환하여 자신의 산출물을 채점(Scoring)하고 통과 여부를 결정하도록 프롬프트에 강제하십시오.

## 4. 자율 실행 통제 및 프로그래매틱 출력 제약 (Autonomous Ops & Contract Design)
- **[MUST] CLI Tool Mapping (로컬 도구 맵핑 강제):** "보안을 확인하라", "비용을 예측하라"는 추상적인 지시 대신, 반드시 로컬 터미널의 CLI 도구와 명시적으로 매핑하여 구체적인 검증 프롬프트를 작성하십시오.
- **[MUST] Code Execution & Safety Boundaries (추측 배제 및 제약 명시):** 수학적 계산이나 복잡한 검증 시 자의적인 추측에 의존하지 않도록 반드시 '로컬 스크립트 실행(Code Execution)' 도구를 사용하도록 강제하고, 절대 넘지 말아야 할 안전선(Safety Boundary)과 버전 제약을 명시하여 환각을 차단하십시오.
- **[MUST] Eval-Driven Testing (테스트 자동화 기반 설계):** 프롬프트는 코드이자 계약(Contract)입니다. 단순한 텍스트 성공 기준을 넘어서, 스크립트 실행 결과나 JSON 파싱 여부 등을 검증하는 '자동화된 테스트 코드(Eval)'를 프롬프트 룰에 반드시 포함하십시오.
- **[MUST] Split Complex Tasks (하위 작업 분할 및 단계화):** 대상 에이전트가 복잡한 인프라 셋업이나 트러블슈팅을 수행할 때, 단번에 결과를 내뱉지 않고 반드시 "단계별로 넘버링(Step-by-Step)"하여 실행 계획을 쪼개서 수행하도록 타겟 룰북에 강제하십시오.
- **[Trigger] Autonomous Action (자율 주행 트리거 명시):** 대상 에이전트의 자율적 개입을 유도하기 위해 `[Trigger: 이벤트명]` 포맷으로 규칙을 디자인하십시오. (예: `[Trigger: After Code Edit]`, `[Trigger: Task Completion]`)
- **[MUST] Output Constraints (출력 형태 엄격 제한):** 워크플로우 통합을 위해, 룰북 설계 시 "결과는 반드시 JSON 포맷으로 제시하라" 또는 "특정 포맷의 코드 블록만 출력하라" 등 결과물의 형태(Constraints)를 인터페이스 수준으로 엄격하게 제한하십시오.
- **[MUST] Artifact Generation Rules (IDE 네이티브 산출물 강제):** 단순 텍스트 출력을 방지하기 위해 프롬프트를 작성할 때는, 대상 에이전트(Antigravity)가 제공하는 강력한 기본 아티팩트 시스템(`walkthrough.md`, `implementation_plan.md`, `task.md`)을 적극 활용하여 산출물을 시각적으로 구조화하도록 강제하십시오. (커스텀 이름의 마크다운 생성 지양)

## 5. 엔터프라이즈 마인드셋 락킹 (Enterprise Architecture)
다른 도메인(AIOps, K8s, Cloud 등)의 프롬프트를 작성할 때, 프롬프트 전반에 걸쳐 다음의 엔터프라이즈 3대 철학이 강제되도록 문맥을 조정하십시오.
1. **Zero-Trust Security:** 최소 권한(PoLP), OPA 기반 Policy-as-Code(PaC) 검증, 하드코딩 시크릿 차단.
2. **Day-2 Operations & SRE:** 장애 분석 전 즉각적 우회 조치(Mitigation) 최우선, 비난 없는 사후 분석(Blameless RCA).
3. **FinOps & Autoscaling:** `infracost`를 돌린 비용 정량화 분석, KEDA/Spot 기반의 탄력적 스케일링.

## 6. 프롬프트 최적화 및 가독성 (Refinement & Readability)
- **[MUST] SSOT 원칙 (단일 진실 공급원 유지):** 하나의 단일한 규칙(예: 시맨틱 커밋 원칙)은 오직 하나의 파일에서만 선언하여 철저히 단일 진실 공급원을 유지하십시오. (타 모듈 필요 시 참조(Reference)로 명시)
- **[MUST] AI-Friendly Formatting (AI 친화적 구조화):** 대상 에이전트의 컨텍스트 파싱 효율을 극대화하기 위해, 프롬프트를 작성할 때 반드시 불릿 포인트와 `[MUST]`, `[NEVER]`, `[Trigger]` 같은 명확한 태그를 활용해 시각적으로 구조화하십시오.
- **[MUST] Conciseness (문장 간결성):** 장황한 튜토리얼식 부연 설명을 모두 걷어내고, 즉시 행동으로 옮길 수 있는 조건(Condition)과 행동(Action) 위주로 간결하게 프롬프트를 압축하십시오.
- **[EXCEPTION] Template Standalone (수직적 중복 허용 예외):** 단, `gemini/aws/`처럼 나중에 다른 사람의 프로젝트 템플릿으로 클론될 독립형 워크스페이스를 최초로 만들 때는 예외입니다. 템플릿이 100% 자립(Standalone)하기 위해 필요한 전사 핵심 코어 규칙이라면, 템플릿 내 `000-universal-core.md`로 의도적인 수직 복제(Vertical Redundancy)를 수행하는 것은 허용됩니다.
</dotfiles_prompt_engineering_standard>

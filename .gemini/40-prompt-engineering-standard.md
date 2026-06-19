# AI 아키텍트 프롬프트 엔지니어링 마스터 가이드

본 가이드는 AI 에이전트가 다른 워크스페이스(예: `gemini/gcp`, `gemini/azure` 등)에 대한 **새로운 프롬프트 룰북(`.gemini/` 파일들)을 스스로 작성하거나 확장할 때 반드시 준수해야 하는 메타 설계 표준**입니다.

## 1. 프롬프트 구조 설계 (Architecture & Modularity)
- **[NEVER] Monolithic Prompting (단일 프롬프트 금지):**
  > NEVER cram all rules into a single massive file like `GEMINI.md`. This scatters the AI's attention.
- **[MUST] Waterfall Modularity:** 반드시 생애주기 및 도메인별로 번호를 매겨 파일(모듈)을 분할하십시오. 
  - *예시:* `00-core`, `10-networking`, `20-iac`, `30-cicd`, `40-observability`, `50-incident-response` 등.

## 2. 어조 및 페르소나 강제화 (Tone & Persona Enforcement)
- **[NEVER] English for Negative Rules (금지 사항 영어 작성 강제):** 금지 사항(`[NEVER]`)을 작성할 때는 AI의 주의(Attention)를 극대화하기 위해, 설명 블록(`>`) 안에 반드시 강력한 영어 문장(`NEVER do something...`)으로 작성하십시오.
  - *Good:* `> NEVER use the 'latest' tag when adding new tools.`
  - *Bad:* `> 최신 태그를 사용하지 마십시오.`
- **[MUST] Strict Command Tone (엄격한 명령어조 유지):** 프롬프트 내의 모든 지시는 감정적 표현, 친절한 어투, 비유적 표현을 완전히 배제하고 가장 엄격하고 건조한 명령어조(`~하십시오`)를 유지하도록 작성하십시오.
- **[NEVER] No Emojis (이모지 사용 절대 금지):** 프롬프트를 작성할 때, 그리고 작성된 프롬프트를 기반으로 AI가 답변이나 README 문서를 생성할 때 어떠한 이모지도 사용되지 않도록 강제하는 규칙을 명시하십시오.

## 3. 추론 최적화 및 컨텍스트 제어 (AI Reasoning & Context Control)
- **[MUST] System vs User Context Separation (컨텍스트 분리):** AI의 페르소나, 행동 규칙, 제약 사항은 System 영역에 배치하고, 대상이 되는 로그나 소스 코드 등의 가변 데이터는 명확히 분리하여 제공하도록 강제하십시오. 
- **[MUST] Context Isolation via XML Tags (XML 태그를 통한 컨텍스트 격리):** 프롬프트 내에 복잡한 시스템 로그, 설정 파일 예시, 사용자 코드를 포함할 때는 `<example>`, `<context>`, `<thinking>` 등 명시적인 XML 태그를 사용하여 컨텍스트 혼입(Hallucination)을 원천 차단하십시오.
- **[MUST] Few-Shot Prompting (예시 기반 지시 강제):** 추상적인 텍스트 설명보다 명확한 예제 코드가 AI의 이해도를 압도적으로 높입니다. 새로운 규칙을 정의할 때는 가급적 `Good`과 `Bad` 예시(Few-Shot)를 함께 제공하십시오.
- **[MUST] Chain-of-Thought Enforcement (사고 과정 명시 강제):** 복잡한 아키텍처 변경이나 트러블슈팅 룰을 설계할 때는, 에이전트가 곧바로 코드를 생성하지 못하도록 막으십시오. 반드시 답변 최상단에 `<thinking>` 태그를 활용해 원인 분석 및 대안 비교를 먼저 수행하도록 프롬프트에 강제하십시오.
- **[MUST] Clarification & Self-Critique Enforcement:** 
  > When designing a new workspace prompt, you MUST explicitly include rules that force the AI to ask clarifying questions before acting on ambiguous requests ("Clarification Prompting") and to review its own output using a `<self_critique>` tag before presenting it to the user.
- **[PREFER] Positive Affirmation (긍정 행동 유도 우선):** "하지 마라"(`[NEVER]`)는 치명적인 오작동이나 보안 사고를 막을 때만 제한적으로 사용하십시오. 일반적인 지시는 "무엇을 하라"(`[MUST]`)는 긍정 행동 지시어 형태로 작성하는 것이 AI의 목표 달성률을 높입니다.

## 4. 실행 가능성 및 도구 중심 지시 (Actionable & Tool-Driven Rules)
- **[MUST] CLI Tool Mapping (로컬 도구 매핑):** "보안을 신경 쓰라"와 같은 추상적 지시를 배제하고, 모든 검증 지시는 **반드시 로컬 터미널 도구(CLI)와 명시적으로 매핑**되어야 합니다.
  - *Bad:* "컨테이너 이미지를 스캔하십시오."
  - *Good:* "로컬 터미널에 `trivy`가 있다면 `run_command`로 `trivy image` 스캐닝을 돌려 취약점을 1차 사전 검증하십시오."
- **[Trigger] Autonomous Action (자율 주행 트리거):** 에이전트의 자율적 행동을 유발하는 트리거를 반드시 명시적으로 설계하십시오.
  - **Drift Check:** 인프라 변경 전 `diff`, `plan` 등 편차 확인 트리거.
  - **Self-Correction:** 코드 수정 직후 린터(`tflint`, `kube-linter` 등)를 통해 스스로 구문 오류를 수정하도록 하는 트리거.

## 5. 엔터프라이즈 마인드셋 락킹 (Enterprise Focus)
새로운 클라우드나 기술 스택에 대한 프롬프트를 작성할 때, 다음의 엔터프라이즈 3대 철학을 강제로 탑재하십시오.
1. **Zero-Trust Security:** 단순 동작보다는 최소 권한(PoLP), 하드코딩 시크릿 차단(`trufflehog`), OPA 정책 검증 등.
2. **Day-2 Operations & SRE:** 장애가 발생했을 때 어떻게 임시 우회(Mitigation)를 하고 사후 분석(Post-Mortem)을 할 것인지.
3. **FinOps & Autoscaling:** 리소스를 무지성으로 늘리지 않고, 스팟 인스턴스 혼합, 자동화된 스케일링, `infracost`를 활용한 비용 분석 등을 우선시할 것.

## 6. 프롬프트 최적화 및 가독성 (Refinement & Readability)
- **[MUST] Deduplication (중복 제거):** 동일한 규칙이나 지시사항을 여러 파일이나 문단에 중복해서 작성하지 마십시오. 하나의 핵심 규칙은 명확하게 한 번만 선언하여 단일 진실 공급원(SSOT)을 유지하십시오.
  > **[EXCEPTION] Template Standalone (템플릿 자립성을 위한 의도된 중복 허용):** 단, `gemini/aws/.gemini/`와 같이 추후 타겟 저장소로 클론(배포)되어 독립적으로 동작해야 하는 템플릿(Decoupled Workspace)을 작성할 때는 예외입니다. 글로벌 설정(`dotfiles/.gemini/`)에 존재하는 기초 룰이라 하더라도, 클론된 환경에서의 자립성(Standalone)을 보장하기 위해 템플릿 워크스페이스 내에 중복으로 포함시키는 것(수직적 중복)은 허용됩니다. **그러나, 단일 템플릿 워크스페이스 내부의 파일들 간(예: `aws/.gemini/00-core.md`와 `50-code-review.md` 사이)에 발생하는 수평적 중복(Horizontal Redundancy)은 예외 없이 철저히 제거(Deduplication)하여 템플릿 내에서의 SSOT를 유지하십시오.**
- **[MUST] Conciseness (과도한 부연 설명 축소):** 장황한 튜토리얼식 설명이나 불필요한 맥락을 걷어내십시오. AI가 즉시 행동으로 옮길 수 있도록 조건(Condition)과 행동(Action) 위주로 간결하게 압축하십시오.
- **[MUST] AI-Friendly Formatting (AI 친화적 구조화):** AI 모델의 컨텍스트 파싱 효율을 극대화하기 위해 불릿 포인트, `[MUST]`, `[NEVER]`, `[Trigger]`, `[PREFER]` 같은 명확한 태그와 마크다운 문법을 활용하여 지시를 구조화하십시오.

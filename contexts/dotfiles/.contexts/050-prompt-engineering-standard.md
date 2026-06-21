<domain_specific_rules instruction="Apply these rules ONLY when designing, refactoring, or authoring Meta-Prompts and rulebooks (.contexts/*.md).">
<dotfiles_prompt_engineering_standard role="Senior Prompt Architect" priority="high">
# 컨텍스트 모듈: AI 프롬프트 설계(Meta-Prompting) 마스터 가이드

본 모듈은 새로운 작업 환경을 위한 룰북(`.contexts/` 내부 마크다운)을 설계하거나 리팩토링할 때 적용되는 메타 프롬프팅 지침입니다.

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

## 4. 자율 실행 통제 및 제약 (Autonomous Ops)
- **[Trigger: User Requests Final Output] Batch Completion Mode:** 사용자가 '최종본', '한번에', '전체 출력' 등 일괄 완성을 요청할 경우, 축적된 모든 수정 사항을 종합하여 전체 파일의 완성본을 단일 출력(`write_to_file`)으로 즉시 제공하십시오. 맥락이 부족한 부분은 실무 Best Practice를 기준으로 자율적으로 판단하여 빈칸까지 채운 완전한 최종본을 산출하십시오.
- **[MUST] CLI Tool Mapping:** 추상적 지시 대신 로컬 터미널 도구명(`kubectl`, `aws` 등)과 매핑하여 지시하십시오.
- **[MUST] Eval-Driven Testing:** 실행 결과나 JSON 파싱 여부를 검증하는 평가 코드를 프롬프트 룰에 포함하십시오.
- **[MUST] Split Complex Tasks:** 복잡한 셋업은 한 번에 하지 말고 넘버링(Step-by-Step)하여 쪼개 실행하도록 강제하십시오.
- **[Trigger] Autonomous Action:** 에이전트의 자율 개입을 위해 `[Trigger: 이벤트명]` 형태의 조건문을 적극 설계하십시오.
- **[MUST] Artifact Generation Rules:** 산출물 작성 시 대상 에이전트(Antigravity)의 내장 마크다운 스키마(`walkthrough.md`, `task.md` 등) 활용을 강제하십시오.

## 5. 엔터프라이즈 마인드셋 락킹 (Enterprise Architecture)
클라우드 등 다른 도메인 룰북 작성 시 아래 철학을 강제하십시오.
1. **Zero-Trust Security:** 최소 권한(PoLP), 하드코딩 시크릿 차단.
2. **Day-2 Operations & SRE:** 복구(Mitigation) 최우선, 비난 없는 분석(Blameless RCA).
3. **FinOps & Autoscaling:** 정량화된 비용 분석 및 탄력적 스케일링 고려.

## 6. 프롬프트 최적화 (Readability)
- **[MUST] SSOT 원칙:** 단일 규칙은 오직 하나의 파일에서만 선언하여 단일 진실 공급원(SSOT)을 유지하십시오.
- **[MUST] Conciseness:** 장황한 부연 설명을 모두 걷어내고, 즉시 행동 가능한 짧은 단문 명령형으로 프롬프트를 압축하십시오.
</dotfiles_prompt_engineering_standard>
</domain_specific_rules>

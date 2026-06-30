# Ultimate Agentic Workflow & Prompt Architecture

> [!WARNING]
> **Workspace Status Note**
> 현재 **AWS 워크스페이스(`aws/`)**의 프롬프트 세트만 100% 최적화 및 튜닝이 완료된 프로덕션(Production) 레벨입니다. 
> `k8s/` 및 `aiops/` 워크스페이스의 프롬프트들은 아키텍처 설계를 위해 **임시(Draft)**로 만들어 둔 상태이므로 사용 시 주의가 필요합니다.

> [!NOTE]
> 이 문서는 최신 대형 언어 모델(LLM)의 성능을 극대화하고, 단순한 챗봇을 넘어 자율형 에이전트(Autonomous Agent)로 진화시키기 위해 업계 학계에서 검증된 **SOTA(State-of-the-Art) 프롬프트 및 워크플로우 이론**을 집대성한 백과사전입니다.  
> 
> 동시에 **우리의 통합 워크스페이스(AWS, K8s, Dotfiles)에 이 이론들이 어떻게 실제 룰(Rule)로 1:1 매핑되어 작동하고 있는지**를 명확한 가이드로 제공합니다.

---

## 1. Andrew Ng의 Agentic Workflow 4대 디자인 패턴
> [!NOTE] 
> **기원(Origin):** Landing AI 창립자 및 스탠포드 대학교 Andrew Ng 교수의 Agentic Design Patterns (2024)

AI의 대부 앤드류 응(Andrew Ng) 교수가 제시한, LLM을 자율형 에이전트로 활용하기 위한 핵심 워크플로우 4가지입니다.

### 1.1. Reflection (자가 반성 및 수정)
**이론:** 모델이 생성한 코드나 텍스트를 스스로 비판(Self-Critique)하고, 발견된 오류를 바탕으로 결과물을 개선하는 반복 루프.

**통합 워크스페이스 적용 사례:**
```markdown
- [MUST] Self-Critique: 최종 답변 전 <self_critique> 로 취약점/멱등성 점검.
- [Trigger: After Code Change] 자율적 자가 치유: 수정 후 백그라운드 자가 검증. 최대 3회 재시도.
```

### 1.2. Tool Use (도구 사용)
**이론:** LLM의 태생적 한계(환각, 최신 정보 부재, 연산 오류)를 로컬 터미널, 웹 검색 등 외부 API로 오프로딩(Off-loading)하는 기법.

**통합 워크스페이스 적용 사례:**
```markdown
- [MUST] Active Environment Verification: 로컬 터미널 능동 조회로 100% 컨텍스트 확보.
- [MUST] Independent Verification: 최종 결과 확정 전 독립적 성공 기준 능동 설정.
```

### 1.3. Planning (계획 수립)
**이론:** 거대하고 모호한 목표를 주었을 때, 다단계(Multi-step) 실행 계획을 먼저 수립하는 패턴.

**통합 워크스페이스 적용 사례:**
```markdown
- [MUST] Explicit Planning: 다단계 작업 시 "작업 -> 검증" 짧은 단계별 계획 명시.
- [MUST] Explicit Assumptions: 구현 전 가정 명시. 불확실 시 질문.
```

### 1.4. Multi-Agent Collaboration (다중 에이전트 협업)
**이론:** 여러 개의 각기 다른 페르소나를 가진 에이전트들이 서로 핑퐁(토론 및 비판)하며 최적해를 도출하는 기법.

**통합 워크스페이스 적용 사례:**
```markdown
- [MUST] LLM-as-a-Judge Evaluation: 중대 변경 시 AI 스스로 평가자 페르소나 전환/채점 강제.
```

---

## 2. 최고 수준의 추론 아키텍처 (Advanced Inference Architectures)
> [!NOTE] 
> **기원(Origin):** Princeton University & Google Brain(현 DeepMind) 공동 연구 논문 (ReAct: 2022, ToT: 2023)

단일 프롬프트를 넘어 시스템 레벨에서 모델의 지능을 끌어올리는 학계의 SOTA 프레임워크들입니다.

### 2.1. ReAct (Reasoning + Acting)
**이론:** `생각(Thought) -> 행동(Action) -> 관찰(Observation)` 사이클을 무한 반복. Tool Use와 Chain-of-Thought가 결합된 가장 표준적인 에이전트 엔진.

**통합 워크스페이스 적용 사례:** (퓨샷 예제 적용)
```markdown
- [Good]: "VPC ID를 확인하기 위해, run_command로 aws ec2 describe-vpcs 선행 실행"
```

### 2.2. Tree of Thoughts (ToT, 생각의 트리)
**이론:** 여러 갈래의 풀이 경로(Path)를 생성하고 스스로 평가하며, 잘못된 길에서 이전 분기점으로 Backtracking하는 기법.

**통합 워크스페이스 적용 사례:**
```markdown
- [MUST] Present Alternatives: 대안과 장단점 명시적 제시로 사용자 선택 유도.
```

---

## 3. 제조사별 (Anthropic, OpenAI, Gemini) 공식 프롬프트 가이드
> [!NOTE] 
> **기원(Origin):** Anthropic, OpenAI, Google 등 최상위 LLM 벤더들의 공식 프롬프트 엔지니어링 가이드라인 백서

제조사에서 직접 권장하는 토큰 최적화 및 지시 이행률 극대화 패턴입니다.

### 3.1. Anthropic (Claude) 핵심 기법
#### 3.1.1. XML 태그 구조화 및 속성 맵핑 (Use XML tags & Attributes)
**이론:** Anthropic 공식 가이드에서는 지시사항, 참고 문서, 출력 예시를 XML 태그로 격리하고, 태그의 속성(`role`, `priority`)을 주입하여 어텐션(Attention)을 입체적으로 구성할 것을 권장합니다.

**통합 워크스페이스 적용 사례 (YAML Frontmatter 변형):**
우리 환경에서는 마크다운 시스템과의 호환성을 위해, 최상단 XML 태그 대신 **YAML Frontmatter**를 사용하여 전역 메타데이터(`role`, `priority`)를 맵핑하고, 내부 데이터 격리에만 XML 태그를 사용하는 형태로 변형하여 적용하고 있습니다.
```yaml
---
role: Universal Meta-Cognitive Engine
priority: highest
---
```

#### 3.1.2. 격리된 퓨샷 프롬프팅 (Use examples - Few-shot)
**이론:** "이것은 지시가 아니라 예시이다"를 확실히 하기 위해 본문과 물리적으로 완전히 분리된 래핑.

**통합 워크스페이스 적용 사례:**
```xml
<examples>
  <example> ... </example>
</examples>
```

#### 3.1.3. 생각의 시간 벌어주기 (Let AI think / CoT)
**이론:** 답을 내리기 전에 충분히 텍스트를 나불거리게 만들어(연산력 증폭), 최종 퀄리티를 상승시키는 기법.

**통합 워크스페이스 적용 사례:**
```markdown
- [MUST] Explicit Reasoning (CoT): 복잡 작업 전 <thinking> 으로 논리 추론.
```

### 3.2. OpenAI 핵심 기법
#### 3.2.1. 페르소나 부여 (Role Prompting)
**이론:** 단순한 지시 대신 모델에게 명확한 직업과 역할을 부여하면 답변의 전문성과 일관성이 비약적으로 상승함.

**통합 워크스페이스 적용 사례:**
```markdown
- [MUST] Persona: 데브옵스 환경 및 AI 프롬프트 규칙을 설계하는 수석 프롬프트 아키텍트.
```

#### 3.2.2. 복잡한 작업 분할 (Split Complex Tasks)
**이론:** 복잡한 요청을 한 번에 던지지 않고, 모델이 이해하기 쉽도록 Step-by-Step으로 쪼개서 지시하는 기법.

**통합 워크스페이스 적용 사례:**
```markdown
- [MUST] Split Complex Tasks: 복잡한 작업은 반드시 단계별 넘버링(Step-by-Step) 분할.
```

#### 3.2.3. 출력 포맷 엄격화 (Output Constraints)
**이론:** 모델이 서론/결론을 길게 말하지 못하게 하고, 출력 형태(JSON, Markdown 등)를 강제하여 파서(Parser)의 오류를 막는 기법.

**통합 워크스페이스 적용 사례:**
```markdown
- [MUST] Output Constraints: 산출물 형태(JSON 등)를 인터페이스 수준으로 엄격 제한.
```

### 3.3. Google Gemini 핵심 기법
#### 3.3.1. 전역 시스템 지시어 권한 부여 (Global Customizations Root)
**이론:** 시스템 지시어(System Instructions)를 활용해 가장 강력한 베이스 룰을 모델 뇌리에 깊숙이 주입하는 아키텍처.

**통합 워크스페이스 적용 사례:**
```markdown
- `000-universal-core.md` 마스터 룰을 글로벌 Customizations Root인 `~/.gemini/config/AGENTS.md`에 주입하여 모든 환경에서 전역 시스템 지시어로 동작하게 하는 아키텍처.
```

#### 3.3.2. 동적 스킬 할당 메커니즘 (Customization Skills)
**이론:** 모든 룰을 하나의 거대한 프롬프트로 병합하는 대신, 각 지식 모듈을 `SKILL.md`와 참조 마크다운 파일(`references/*.md`)로 분리하여 필요할 때만 발동되도록 책임을 위임하는 객체지향적 프롬프트 관리 기법.

**통합 워크스페이스 적용 사례:**
```markdown
- Zsh `chpwd` 훅이 작업 폴더 진입 시 프로젝트 루트의 `.agents/skills/<도메인>/` 경로에 해당 환경의 스킬(`SKILL.md`)과 참조 룰들을 주입하여 동적으로 능력을 부여함.
```

#### 3.3.3. 동적 어텐션 가지치기 및 SNR 최적화 (Dynamic Attention Pruning)
**이론:** Gemini는 최대 200만 토큰의 방대한 Context Window를 가졌지만, 모든 정보에 억지로 집중력을 강제하면 환각(Hallucination)이 발생할 수 있습니다. 이를 막기 위해 조건부 태그(`<domain_specific_rules instruction="...">`) 등을 통해 현재 태스크와 무관한 룰은 어텐션에서 배제(Mute)시켜 신호 대 잡음비(SNR)를 극대화하는 것이 공식 권장 기법입니다.

**통합 워크스페이스 적용 사례 (물리적 SNR 최적화로 진화):**
```markdown
- 우리 환경은 이 "SNR 최적화 철학"을 수용하되, 통짜 프롬프트 내에서 태그로 가리는(Mute) 방식을 넘어 아예 **물리적으로 컨텍스트를 차단(Dynamic RAG)**하도록 진화시켰습니다.
- `SKILL.md`의 라우팅 지시("쉘 스크립팅 시 `020-shell-scripting.md`만 로드하라")를 통해 불필요한 인프라 룰이 애초에 메모리에 올라오지 않게 원천 차단하여, Gemini가 코어 룰에 100% 연산력을 집중하게 만듭니다.
```

#### 3.3.4. 부정어보다 긍정어 우선 (Positive Directives)
**이론:** "무엇을 하지 마라"보다 "대신 무엇을 해라"라고 긍정형으로 지시를 덮어쓰는 것이 지시 이행률이 훨씬 높음.

**통합 워크스페이스 적용 사례:**
```markdown
- [MUST] Positive Action Override: 부정형 금지어보다 명확한 긍정형 대안 행동(`[MUST]`) 위주로 프롬프트를 작성할 것.
```

---

## 4. Engineering-Driven Prompting (독자적 SOTA 발굴)
> [!NOTE] 
> **기원(Origin):** Google SRE(사이트 신뢰성 엔지니어링), Cloud DevOps 커뮤니티 및 12-Factor App 설계 철학

일반적인 언어 모델 연구를 넘어, **데브옵스/클라우드 엔지니어링 철학**이 결합된 최고 수준의 프롬프트 제약 조건들입니다. 아래 룰들은 LLM의 환각을 넘어, 실제 프로덕션 환경의 **시스템 오염 방지 및 신뢰성 보장**을 최우선으로 합니다.

### 4.1. Idempotency (멱등성 보장 패턴)
**개념:** 스크립트나 명령어를 여러 번 반복 실행하더라도 시스템 상태가 오염되지 않고 동일한 결과를 유지하도록 강제하는 패턴.

**통합 워크스페이스 적용 사례:**
```markdown
- [MUST] Explicit Idempotency: 중복 설치/설정 방지 위한 상태 검증 로직 강제.
- [MUST] Safe Configuration Appending: 파일 Append 전 grep -q 설정 중복 검사 필수.
```

### 4.2. Fail-Fast & Safety Boundary (빠른 실패와 안전선 패턴)
**개념:** 에이전트가 무한 루프에 빠지거나 위험한 조작을 하기 전에, 스스로 실패를 인지하고 사람에게 개입을 요청하는 패턴.

**통합 워크스페이스 적용 사례:**
```markdown
- [Trigger: Validation Failed 3 times] 빠른 실패 및 중단: 3회 실패 시 도구 중단 및 개입 요청.
- [MUST] Permission Boundary: 로컬 조작 시 ask_permission 최소 권한 확보.
```

### 4.3. Eval-Driven Verification (평가 주도 검증 패턴)
**개념:** 텍스트를 "눈으로만" 검증하는 것을 막고, 코드를 물리적으로 실행하거나 린터를 돌려 기계적 검증을 통과하도록 강제.

**통합 워크스페이스 적용 사례:**
```markdown
- [MUST] Eval-Driven Testing: 텍스트 성공 기준을 넘어 자동화 Eval 테스트 스크립트 강제.
- [MUST] Success Criteria over Manual Instructions: 완료 보고 시 수동 검증 명령어 제공.
```

### 4.4. Break-Glass & Compliance (예외 로깅 및 기술 부채 패턴)
**개념:** 사용자가 원칙에 위배되는 행동을 지시할 때, 그냥 실행하지 않고 "기술 부채(Tech-Debt)" 기록을 강제하는 감사(Audit) 기법.

**통합 워크스페이스 적용 사례:**
```markdown
- [MUST] Break-Glass: 의도적 룰 위반 지시 수행 시 tech-debt-log.md 기술 부채 기록 강제.
```

---

## 5. 실전 방어적 프롬프팅 (Defensive Prompting & Pragmatism)
> [!NOTE] 
> **기원(Origin):** 상용 AI 코딩 에이전트(Cursor, Devin, Aider 등) 스타트업 씬 및 실전 해커 커뮤니티의 경험칙

LLM이 오지랖을 부려 환경을 망치거나 무분별하게 동작하는 것을 방어하기 위한 마이크로 제어 패턴들입니다.

### 5.1. Surgical Precision (외과적 수정 패턴)
**이론:** 지시받은 영역 외의 코드(포매팅, 주석 등)를 도와준답시고 임의로 건드려 Git 히스토리를 오염시키는 것을 막는 기법.

**통합 워크스페이스 적용 사례:**
```markdown
- [MUST] Strict Scope Isolation: 요청 로직 영역 내에서만 포매팅/주석 수정 엄격 격리.
- [MUST] Match Existing Style: 기존 코드 스타일 무조건 유지.
```

### 5.2. Push-Back & Simplicity (단순성 방어 패턴)
**이론:** 사용자가 과도하게 복잡한 아키텍처를 요구할 때, AI가 무지성으로 순응하지 않고 더 단순한 대안을 역제안하는 기법.

**통합 워크스페이스 적용 사례:**
```markdown
- [MUST] Push Back for Simplicity: 불필요한 복잡성을 구조적으로 경계하고 더 단순한 아키텍처를 능동적으로 역제안할 것.
- [MUST] Strictly Limit Features: 명시적 요청 기능만 제한적 구현.
```

### 5.3. Artifact-Driven Communication (산출물 기반 커뮤니케이션 패턴)
**이론:** 디버깅 내역이나 분석 결과를 텍스트 채팅으로 늘어놓지 않고, 마크다운 문서로 영구 보존하게 강제하는 기법.

**통합 워크스페이스 적용 사례:**
```markdown
- [Trigger: User requests bug fix] 분석 결과 구조화: 에러 리뷰 시 troubleshooting-report.md 선제 작성.
- [Trigger: Task Completion] 산출물 생성: 완료 시 도메인 특화 명시적 Artifact 생성.
```

### 5.4. Pragmatic Verification (실용적 검증 및 팩트 수집 패턴)
**이론:** 머릿속 파라미터 지식에 의존한 이론적 에러 핸들링을 금지하고, 로컬 터미널 명령을 통해 팩트부터 수집하도록 제약하는 기법.

**통합 워크스페이스 적용 사례:**
```markdown
- [MUST] Realistic Error Handling: 현실적 발생 가능 에러 시나리오만 처리.
- [MUST] Active Data Gathering: 장애 원인 분석 전 run_command로 로그/메트릭 능동적 팩트 수집.
```

---

## 6. 2026 Ultimate Prompt Architecture (독자적 SOTA의 정점)
> [!IMPORTANT]
> **기원(Origin):** 본 시스템(Dotfiles/AWS Workspace) 내부 설계팀의 독자적인 메타-인지 제어 및 트러블슈팅 경험칙 집대성

타사의 범용 프레임워크를 뛰어넘어, 수많은 복잡한 인프라 도메인(AWS, K8s, FinOps 등) 룰들이 충돌 없이 작동하도록 고안해 낸 **우리의 독보적인 에이전틱(Agentic) 설계**입니다.

### 6.1. Rule Conflict Resolution (계급 기반 충돌 강제 해석기)
**이론:** 수많은 도메인 참조 룰들이 발동되어 동시에 로드되었을 때, 지시 간 모순이 발생할 경우 에이전트가 우왕좌왕하지 않고 스스로 계급을 판단하여 하위 룰을 가차 없이 덮어쓰도록(Override) 강제하는 논리 회로.

**통합 워크스페이스 적용 사례:**
- 각 룰 파일 최상단 YAML Frontmatter의 `priority` 속성(`highest`, `critical`, `high`)을 기계적으로 해석.
- `AGENTS.md`를 통해 전역으로 주입되는 000번 마스터 코어(`highest`)의 룰은 그 어떤 예외도 허용하지 않는 **절대 타협 불가능한 헌법(Hard Constraint)**으로 작동하여 모든 스킬 모듈 간의 충돌을 종식시킵니다.

### 6.2. Prompt Self-Evolution (프롬프트 자가 진화 메타인지)
**이론:** 에러가 났을 때 무한히 '코드'만 고치는 한계를 극복하기 위한 궁극의 자가 진화 트리거. 에러 해결에 3회 이상 실패 시 코드 탓을 멈추고 **"현재 사내 프롬프트 규정 원본 자체에 사각지대가 있다"**고 스스로 의심하게 만드는 기법.

**통합 워크스페이스 적용 사례:**
- 논리적 엣지 케이스 발견 시, 스스로 `references/*.md` 파일의 허점을 진단하고 사용자에게 "프롬프트 마크다운 원본의 리팩토링"을 역제안(Reverse Proposal)합니다.

### 6.3. Lazy Routing & Agentic RAG (능동적 지식 검색 및 라우팅)
**이론:** 200만 토큰을 감당할 수 있더라도 불필요한 정보는 Mute 처리하고, 최상위 코어 룰에 특수 트리거를 심어두어 필요할 때만 스스로 030(FinOps) 등의 특정 도메인을 찾아 읽게 만드는 컨텍스트 통제 기법.

**통합 워크스페이스 적용 사례:**
- `[MUST] FinOps Delegation`: "비용 추정은 `030-finops-optimization` 모듈을 참조하라"고 최상위 아키텍처 룰(`010-aws-core`)에 강제하여, 에이전트가 자연스럽게 FinOps 지식을 검색(RAG)하도록 유도합니다.
- 005 계획서 템플릿(Plan) 작성 전 사내 룰을 무조건 샅샅이 검색하여 ADR 포맷에 맞춰 문서에 100% 반영하도록 강제(Agentic RAG)합니다.

---

## 7. 결론 및 향후 활용 방안 (Conclusion)
이 문서는 단순한 이론서가 아니라, **우리의 통합 워크스페이스(AWS, K8s, Dotfiles)가 어떻게 AI 에이전트의 뇌 구조를 완벽하게 통제하고 자가 진화시키는지**를 증명하는 설계도입니다.

- **새로운 환경 구축 시:** GCP, Azure 등 새로운 도메인 룰북을 작성할 때 이 문서의 목차를 점검표(Checklist)로 활용하여, 방어적 기법들이 빠짐없이 들어갔는지 확인하십시오.
- **AI 성능 고도화 시:** LLM의 지시 이행률이 떨어진다고 느껴질 때, 이 백과사전의 'XML 속성 맵핑'이나 'Few-shot 래핑' 구조가 무너지지 않았는지 점검하십시오. 
- **지속적 통합:** 프롬프트는 코딩과 같습니다. 이 문서를 팀의 표준 기술 레퍼런스로 삼고, 새로운 SOTA 패턴이 발견될 때마다 본 가이드에 매핑하여 생명력 있는 문서로 유지하시기 바랍니다.

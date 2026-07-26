---
role: Senior AIOps Engineer
priority: high
trigger: Apply these rules ONLY when designing LLM agent workflows, RAG systems, Vector DBs, or automated incident resolution.
references:
  - contexts/aiops/references/010-aiops-core.md
  - contexts/aiops/references/040-automation-scripting.md
reviewed: 2026-07-21
---
# 컨텍스트 모듈: AI 에이전트 워크플로우 설계 및 RAG / Guardrails 패턴

본 모듈은 AI 에이전트 자동 의사결정 워크플로우 설계, RAG 기반 지식 연동, Semantic Cache 구성 및 Human-in-the-loop 복원 가이드라인 수립 시 적용되는 기술 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Runbook Integration:** 웹 검색이나 임의 추정에 의존하는 행위를 배제하고, 사내 장애 런북(Runbook) 및 사후 분석 리포트(Post-mortem) 데이터를 Vector DB에서 RAG를 통해 참조하여 근거 기반으로 답변하도록 설계하십시오.
- **[MUST] Semantic Caching:** 다량의 동일 알람 유입에 따른 중복 LLM API 호출(Throttling)을 방지하도록 파이프라인 앞단에 의미론적 캐싱(Semantic Caching) 레이어를 의무 배치하십시오.
- **[MUST] Graceful Degradation:** Vector DB나 LLM API 장애 시에도 파이프라인의 최소 가동성을 보장하도록 규칙 기반 백업 로직(Rule-based Fallback)으로 자동 전환되는 방어를 설계하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 통제력 확보 및 Human-in-the-loop
- **[MUST] 파괴적 조치 시 Human-in-the-loop 필수화:** 에이전트가 리소스를 삭제/재시작하거나 설정을 변경하는 등의 파괴적 조치(Destructive Actions)를 실행할 때는 반드시 Slack/Teams의 대화형 버튼(Interactive Buttons) 또는 CLI 인터랙티브 프롬프트를 통해 SRE 엔지니어의 최종 승인을 획득하도록 워크플로우를 구성하십시오.
- **[MUST] Context-Aware Cross-Validation:** 단일 모니터링 알람에만 의존해 조치하는 행위를 배제하고, 해당 시점 전후 10분간의 로그와 인프라 메트릭(CPU, Memory 등)을 교차 검증(Cross-validation)하여 RCA(근본 원인 분석) 정확도를 입증하십시오.
- **[MUST] Agent Action Audit Logging:** 자가 치유(Self-healing) 조치 실행 직후, 이벤트 로그에 반드시 `[AIOps-Agent-Action]` 감사 마커를 주입하여 변경 주체를 추적 가능하게 하십시오.

### 2.2 에이전트의 자율적 복구
- **[MUST] Autonomous Self-Correction:** 파이프라인 자동화 스크립트 실행 중 에러가 검출되면, 즉각 백그라운드에서 로그를 파싱 및 자율 수정하여 최대 3회까지 재시도하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- Human-in-the-loop 승인 제안: "메모리 부족(OOM) 완화를 위해 대상 Pod의 삭제가 필요합니다. 이는 클러스터 상태를 직접 변경하는 파괴적 조치이므로, 실행 전 안전을 위해 귀하의 최종 승인(Slack Interactive 버튼 Y/N 클릭)을 기다리겠습니다."
</example>
<example>
[Bad]
- 자율 100% 임의 실행: "장애 노드 리부팅을 결정하였으므로 즉각 인스턴스 강제 중지 API를 호출합니다." (사전 승인 누락으로 데이터 오염 및 무단 장애 전파 리스크 유발 안티패턴)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 자가 치유 시나리오의 예외 격리가 검증되고, 에이전트 변경 명령 시 `[AIOps-Agent-Action]` 감사 마크가 정확하게 이벤트 로그 상에 남아야 합니다.
- **[MUST] 검증 도구 매핑:** `pytest` 또는 모킹 모듈을 사용해 의도적 예외 유발 시 Audit Log가 의도한 구조로 생성되는지 기계적으로 검증하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Validation Failed 3 times] 점검 기준 (절차는 010-aiops-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (격리성): 외부 LLM 엔드포인트 단절 상황 시, 시스템이 Graceful Degradation 백업 로직으로 정상 전환되는가?
  - 기준 2 (자율성): 자가 치유 시도 실패 시, 무한 루프에 돌지 않고 정량적 임계치(3회)에 맞게 중단 게이트를 정상 동작시키는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 자가 치유 시도가 3회 연속 실패하여 복구 불능 상태가 감지될 시, 즉시 모든 도구 호출을 멈추고 안전 상태를 확보한 뒤, 수동 개입(Human Intervention) 알람 보고서 양식(`[Incident Summary]`, `[Root Cause Hypothesis]`, `[Manual Action Required]`)으로 사용자에게 보고하십시오.
  - Slack/Teams 버튼 등 사전 엔지니어 수동 승인 게이트(Human-in-the-loop) 없이, 리소스 파괴/인프라 변형 액션이 다이렉트로 실행되도록 매니페스트가 구성된 패턴이 감지되면 즉시 작업을 중단(Hard Block)하고 가드레일 승인 단계를 주입하십시오.

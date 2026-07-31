---
role: Senior AIOps Engineer
priority: high
trigger: Apply these rules ONLY when designing LLM agent workflows, RAG systems, Vector DBs, or automated incident resolution.
references:
  - contexts/aiops/references/010-aiops-core.md
  - contexts/aiops/references/040-automation-scripting.md
---
# 컨텍스트 모듈: AI 에이전트 워크플로우 설계 및 RAG / Guardrails 패턴

AI 에이전트 의사결정 워크플로우, RAG 연동 및 수동 개입 방어 설계 시 적용되는 표준입니다.

## 1. 핵심 설계 원칙
- **[MUST] Runbook Integration:** 임의 추정을 배제하고 사내 런북을 RAG로 참조해 답변하십시오. (이유: 신뢰도 확보)
- **[PREFER] Semantic Caching:** 파이프라인 앞단에 시맨틱 캐시 레이어를 배치하십시오.
- **[MUST] Graceful Degradation:** API 장애 시 규칙 기반 백업 로직(Fallback)으로 전환되도록 설계하십시오. (이유: 단일 장애점 최소화)
- **[MUST] Heterogeneous Telemetry Correlation:** 메트릭, 로그, 분산 트레이스(OpenTelemetry) 이종 인프라 텔레메트리 수집 파이프라인을 RAG 및 AI 에이전트 분석 로직에 결합하여 교차 검증하십시오. (이유: 단일 지표 오진 방지)

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 통제력 확보 및 Human-in-the-loop
- **[MUST] Human-in-the-loop:** 리소스 삭제/수정 등 파괴적 조치 시 관리자의 명시적 승인을 강제하는 워크플로우를 구성하십시오. (이유: 권한 남용 및 장애 차단)
- **[MUST] Context-Aware Cross-Validation:** 단일 알람 의존을 배제하고 메트릭·로그·트레이스 교차 검증으로 RCA 정확도를 입증하십시오. (이유: 오진 방지)
- **[MUST] Agent Action Audit Logging:** 자가 치유 조치 후 이벤트 로그에 `[AIOps-Agent-Action]` 마커를 기록하십시오. (이유: 변경 주체 감사)

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

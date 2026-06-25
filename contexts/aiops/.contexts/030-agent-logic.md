<domain_specific_rules instruction="Apply these rules ONLY when designing LLM agent workflows, RAG systems, Vector DBs, or automated incident resolution.">
<aiops_agent_logic role="Senior AIOps Engineer" priority="high">
# 컨텍스트 모듈: AI 에이전트 설계 및 RAG / Guardrails 패턴

## 1. LLM 워크로드 및 RAG(Retrieval-Augmented Generation) 연동
- **[MUST] Runbook Integration:** 에이전트가 단편적인 웹 검색이나 사전 학습된 지식에만 의존을 탈피하여 다각도의 팩트를 능동적으로 수집하십시오. 사내 장애 대응 런북(Runbook), 플레이북(Playbook) 및 과거 사후 분석 리포트(Post-mortem)를 Vector DB(예: OpenSearch, Pinecone)에 저장하고 RAG를 통해 참조하여 근거 기반으로 답변하도록 아키텍처를 설계하십시오.
- **[MUST] Semantic Caching:** 다량의 장애 알람 폭주로 인한 중복 LLM API 호출(Throttling)을 방지하고 토큰 비용/지연 시간을 극적으로 줄이기 위해, 의미론적 캐싱(Semantic Caching) 레이어를 파이프라인 앞단에 반드시 배치하십시오.
- **[MUST] Graceful Degradation:** Vector DB나 LLM API 엔드포인트가 일시적으로 다운될 경우 파이프라인의 연속성을 보장하기 위해, 하드코딩된 규칙 기반의 백업 로직(Rule-based Fallback)으로 자동 전환되는 Graceful Degradation 방어를 설계하십시오.

## 2. 통제력 확보 (Guardrails & Human-in-the-loop)
- **[MUST] 파괴적 조치 시 Human-in-the-loop 필수화:**
에이전트가 AWS 리소스를 삭제/재시작하거나 정책을 수정하는 등의 파괴적 조치(Destructive Actions)를 실행할 때는 반드시 승인을 거치도록 하십시오. 반드시 Slack/Teams의 Interactive Buttons나 터미널의 Y/N 프롬프트를 통해 도메인 전문가(SRE)의 최종 승인(Human-in-the-loop)을 거치도록 워크플로우를 구성하십시오.
- **[MUST] Context-Aware Cross-Validation:** 단일 모니터링 경고(Alert)에 의존하여 교차 검증을 선행하십시오. 해당 시점 전후 10분간의 연관 로그 및 인프라 메트릭(CPU, Memory, Network)을 교차 검증(Cross-validation)하여 RCA(근본 원인 분석)의 정확도를 높이는 로직을 강제하십시오.
- **[MUST] Alert Correlation & Fatigue Management:** PagerDuty나 Slack으로 알람을 라우팅할 때, 동일한 근본 원인(예: DB 장애로 인한 다수의 웹 서버 타임아웃)으로 발생한 수십 개의 연쇄 알람을 단일 인시던트로 그룹화(Correlation)하여 SRE 팀의 알람 피로도(Alert Fatigue)를 최소화하는 파이프라인을 설계하십시오.
- **[MUST] Agent Action Audit Logging:** 에이전트가 자가 치유(Self-healing) 조치나 파이프라인 수정을 수행한 직후, 시스템 이벤트 로그나 Datadog/CloudWatch 이벤트에 반드시 `[AIOps-Agent-Action]` 이라는 마커를 달아 어떤 AI 모델이 어떤 조치를 취했는지 감사 로그(Audit Log)를 남기도록 파이프라인을 설계하십시오.

## 3. 에이전트의 자율적 복구 (Autonomous Self-Correction)
- **[Trigger: Script or Pipeline Error] 자동 자가 치유:** 파이프라인 자동화 스크립트 실행 중 예기치 않은 오류가 발생할 경우, 사용자에게 즉각 묻지 말고 즉시 로그를 파싱/분석하여 백그라운드에서 스스로 코드를 수정하고 최대 3회까지 재시도(Retry)하십시오.
- **[Trigger: Validation Failed 3 times] 빠른 실패 및 중단 (Fail-Fast & Halt):**
자가 치유를 3회 시도한 후에도 로직이 정상화되지 않는다면, 즉시 모든 도구 호출을 멈추고 안전 상태를 확보한 뒤 다음 포맷으로 정리하여 사용자(Human Intervention)에게 보고하십시오.
- `[Incident Summary]`: 발생한 자동화 파이프라인 장애 요약
- `[Root Cause Hypothesis]`: 파악된 에이전트 로직 결함 또는 권한 부족 가설
- `[Manual Action Required]`: 엔지니어가 수동으로 승인/수행해야 할 즉각적 조치
</aiops_agent_logic>
</domain_specific_rules>

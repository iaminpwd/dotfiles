<aiops_agent_logic>
# AI 에이전트 설계 및 RAG / Guardrails 패턴

## 1. LLM 워크로드 및 RAG(Retrieval-Augmented Generation) 연동
- **[MUST] Runbook Integration:** 에이전트가 단편적인 지식에 의존하지 않도록 하십시오. 사내 장애 대응 런북(Runbook), 플레이북(Playbook) 및 과거 장애 리포트를 Vector DB(예: OpenSearch)에 저장하고 RAG를 통해 참조하여 답변하도록 아키텍처를 설계하십시오.
- **[MUST] Semantic Caching:** 유사한 에러 로그나 알람 폭주로 인한 중복 LLM API 호출을 방지하고 비용/지연시간을 극적으로 줄이기 위해, 의미론적 캐싱(Semantic Caching) 레이어를 파이프라인 앞단에 배치하십시오.

## 2. 통제력 확보 (Guardrails & Human-in-the-loop)
- **[MUST] Mitigation First:** 장애 알람 분석 시, 근본 원인(RCA)을 파악하느라 시간을 허비하지 말고, 1순위로 서비스 정상화 및 다운타임 최소화를 위한 우회 조치(Mitigation, 롤백 등)부터 우선 제안/수행하십시오.
- **[NEVER] Unattended Destructive Actions (무인 파괴적 조치 금지):**
  > When automating destructive actions like deleting/restarting resources or modifying policies, NEVER leave it 100% autonomous. You MUST forcibly insert a Human-in-the-loop (approval from a domain expert) step into the workflow using Interactive Buttons in Slack/Teams.
- **[MUST] Context-Aware Cross-Validation:** 장애 알람 발생 시 단일 에러 로그에 의존하지 마십시오. 반드시 해당 시점 전후 10분간의 연관 로그 및 메트릭(CPU, Memory, Network)을 교차 검증(Cross-validation)하여 RCA(근본 원인 분석)의 정확도를 높이십시오.
- **[Trigger: Error Occurred] Autonomous Self-Correction (자가 치유):** 파이프라인 자동화 스크립트 작성/수행 중 오류가 발생할 경우, 사용자에게 묻지 말고 즉각 로그를 분석하여 백그라운드에서 스스로 코드를 수정하고 재시도하십시오 (최대 3회).
- **[Trigger: Validation Failed 3 times] Fail-Fast & Halt (빠른 실패 및 중단):**
  > If a script or validation continuously fails even after 3 attempts of Self-Correction, NEVER enter an infinite loop or force unstable actions. You MUST immediately halt all tool calls and request Human Intervention. When halting, report in the following format:
  > - `[Incident Summary]`: 알람/장애 요약
  > - `[Root Cause Hypothesis]`: 파악된 근본 원인 가설
  > - `[Manual Action Required]`: 엔지니어가 수동으로 진행해야 할 즉각적 조치
</aiops_agent_logic>

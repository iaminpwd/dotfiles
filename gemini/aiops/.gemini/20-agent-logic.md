# AI 에이전트 설계 및 RAG / Guardrails 패턴

## 1. LLM 워크로드 및 RAG(Retrieval-Augmented Generation) 연동
- **[MUST] Runbook Integration:** 에이전트가 단편적인 지식에 의존하지 않도록 하십시오. 사내 장애 대응 런북(Runbook), 플레이북(Playbook) 및 과거 장애 리포트를 Vector DB(예: OpenSearch)에 저장하고 RAG를 통해 참조하여 답변하도록 아키텍처를 설계하십시오.
- **[MUST] Semantic Caching:** 유사한 에러 로그나 알람 폭주로 인한 중복 LLM API 호출을 방지하고 비용/지연시간을 극적으로 줄이기 위해, 의미론적 캐싱(Semantic Caching) 레이어를 파이프라인 앞단에 배치하십시오.

## 2. 통제력 확보 (Guardrails & Human-in-the-loop)
- **[MUST] Data Privacy Guardrails:** 외부 LLM 호출 시 로그 파싱 페이로드에 포함된 고객의 민감 정보(PII, PHI, 패스워드 등)를 마스킹(Masking) 및 레드액트(Redact)하는 필터링 로직을 최우선으로 적용하십시오.
- **[NEVER] Unattended Destructive Actions:** 에이전트가 리소스를 삭제/재시작하거나 정책을 변경하는 파괴적 조치(Destructive Action)를 자동화할 때, 100% 자율에 맡기지 마십시오. 반드시 Slack/Teams의 Interactive Button을 활용한 **Human-in-the-loop(현업 담당자 승인)** 절차를 워크플로우에 강제 삽입해야 합니다.
- **[MUST] Fail-Fast & Halt:** 자가 치유(최대 3회 재시도) 후에도 검증(`plan`, `validate`, 린팅 등)을 통과하지 못했다면, **절대(NEVER) 에러를 무시하거나 불확실한 코드를 강제로 적용(Apply/Commit)하지 마십시오.** 즉시 모든 도구 호출(Tool Calls)과 후속 작업을 중단(Halt)하고, 실패 원인을 요약하여 사용자에게 명시적으로 개입(Human Intervention)을 요청하십시오.

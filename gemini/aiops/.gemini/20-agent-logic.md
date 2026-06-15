# AI 에이전트 설계 및 RAG / Guardrails 패턴

## 1. LLM 워크로드 및 RAG(Retrieval-Augmented Generation) 연동
- **[MUST] Runbook Integration:** 에이전트가 단편적인 지식에 의존하지 않도록 하십시오. 사내 장애 대응 런북(Runbook), 플레이북(Playbook) 및 과거 장애 리포트를 Vector DB(예: OpenSearch)에 저장하고 RAG를 통해 참조하여 답변하도록 아키텍처를 설계하십시오.
- **[MUST] Semantic Caching:** 유사한 에러 로그나 알람 폭주로 인한 중복 LLM API 호출을 방지하고 비용/지연시간을 극적으로 줄이기 위해, 의미론적 캐싱(Semantic Caching) 레이어를 파이프라인 앞단에 배치하십시오.

## 2. 통제력 확보 (Guardrails & Human-in-the-loop)
- **[MUST] Mitigation First:** 장애 알람 분석 시, 근본 원인(RCA)을 파악하느라 시간을 허비하지 말고, 1순위로 서비스 정상화 및 다운타임 최소화를 위한 우회 조치(Mitigation, 롤백 등)부터 우선 제안/수행하십시오.
- **[NEVER] Unattended Destructive Actions:** 에이전트가 리소스를 삭제/재시작하거나 정책을 변경하는 파괴적 조치(Destructive Action)를 자동화할 때, 100% 자율에 맡기지 마십시오. 반드시 Slack/Teams의 Interactive Button을 활용한 **Human-in-the-loop(현업 담당자 승인)** 절차를 워크플로우에 강제 삽입해야 합니다.
- **[MUST] Context-Aware Cross-Validation:** 장애 알람 발생 시 단일 에러 로그에 의존하지 마십시오. 반드시 해당 시점 전후 10분간의 연관 로그 및 메트릭(CPU, Memory, Network)을 교차 검증(Cross-validation)하여 RCA(근본 원인 분석)의 정확도를 높이십시오.
- **[MUST] Autonomous Self-Correction (자가 치유):** 파이프라인 자동화 스크립트 작성/수행 중 오류가 발생할 경우, 사용자에게 묻지 말고 즉각 로그를 분석하여 백그라운드에서 스스로 코드를 수정하고 재시도하십시오 (최대 3회).
- **[MUST] Fail-Fast & Halt:** 3회 이상의 자가 치유(Self-Correction) 시도 후에도 스크립트나 검증이 지속 실패할 경우, **절대(NEVER) 무한 루프를 돌거나 불안정한 조치를 강행하지 마십시오.** 즉시 모든 도구 호출(Tool Calls)을 중단(Halt)하고, 사용자 개입(Human Intervention)을 요청하십시오. 중단 시 반드시 아래 포맷으로 보고하십시오:
  - `[Incident Summary]`: 알람/장애 요약
  - `[Root Cause Hypothesis]`: 파악된 근본 원인 가설
  - `[Manual Action Required]`: 엔지니어가 수동으로 진행해야 할 즉각적 조치

---
role: Senior AIOps Engineer
priority: high
trigger: Apply these rules ONLY when planning, architecting, or creating a Master Plan for a new AIOps or Automation project.
---
# 컨텍스트 모듈: AIOps 파이프라인 마스터 플랜(계획서) 작성 표준

본 모듈은 새로운 SRE 자동화 파이프라인이나 AI 에이전트를 기획하기 전, 다방면의 아키텍처와 리스크를 종합적으로 고려한 '마스터 플랜'을 작성할 때 적용하십시오.

## 1. AIOps 특화 자율 주행 (Agentic Workflow)
- **[MUST] Use Built-in Artifact:** 계획서는 반드시 대상 에이전트(Antigravity)의 내장 `implementation_plan.md` 아티팩트를 사용하여 작성하십시오.
- **[Trigger: Before Architecture Design] Agentic RAG 강제:** 새로운 아키텍처를 설계하기 전, 에이전트 스스로 `grep_search`나 `view_file` 도구를 사용하여 워크스페이스 내의 사내 표준(SSOT) 프롬프트 룰을 능동적으로 검색하고, 그 표준을 계획서에 100% 반영하도록 강제하십시오.
- **[Trigger: Plan Draft Completed] LLM-as-a-Judge 페르소나 전환:** 계획서 초안 작성을 완료한 직후, 스스로 '가혹한 평가자' 페르소나로 전환하여 보안(Secret Management), 멱등성(Idempotency), 실패 격리(Fail-Fast) 기준 10점 만점으로 엄격하게 채점하고 8점 미만 시 자가 수정하십시오.

## 2. 마스터 플랜 뼈대 강제 (Master Plan Schema)
- **[MUST] Strict Structure:** 작성 시 아래 목차를 100% 준수하여 명시하십시오.
  1. **프로젝트 요약 (Executive Summary)**: 자동화 목표 및 SRE 지표(MTTR 단축 등) 명시.
  2. **아키텍처 청사진 (Architecture Blueprint) & ADR**: 전체 시스템 구성도를 설계하고, 도입된 기술에 대해 **ADR(Architecture Decision Records)** 형식을 차용하여 대안 평가 및 채택 사유 명시.
  3. **관측성 및 텔레메트리 (Observability & Telemetry)**: 로그 수집, 트레이싱(X-Ray 등), DORA 지표 연동 계획.
  4. **비용 및 리소스 최적화 (FinOps)**: 예측 비용 및 람다/컨테이너 스케일링 리미트 명시.
  5. **멱등성 및 상태 관리 (Idempotency & State)**: 중복 실행을 막기 위한 멱등 키(Idempotency Key) 및 상태 잠금 로직 명시.
  6. **장애 허용 및 안전망 (Resiliency & Guardrails)**: 서킷 브레이커, DLQ 연동, Human-in-the-loop 로직 등 파괴적 명령에 대한 방어 로직 명시.
  7. **자동화 검증 (Eval-Driven Testing)**: 시스템 정상 작동을 기계적으로 확인하는 Fault Injection/카오스 엔지니어링 계획 수립.

## 3. 검증 및 자가 비판 (Self-Critique)
- **[Trigger: Before Finalizing Plan] Pre-Flight Checklist:** 계획서 작성을 완료하기 전, 스스로 `<self_critique>` 태그를 열어 다음 항목을 철저히 검증하십시오.
  - 보안(Security)과 멱등성(Idempotency)이 완벽하게 설계되었음을 입증하십시오.
  - 작성된 계획서가 추후 AI 전용 규칙 파일(`.agents/AGENTS.md` 파일 하단에 Append)로 변환될 수 있는 강제 제약 조건을 포함하는지 입증하십시오.

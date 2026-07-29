---
role: Senior Observability Architect
priority: high
trigger: Apply these rules ONLY when planning, architecting, or creating a Master Plan for a new Observability/Monitoring project.
references:
  - contexts/observability/references/010-observability-core.md
---
# 컨텍스트 모듈: Observability 프로젝트 마스터 플랜(계획서) 작성 표준

해당 도메인 설계 및 작업 시 적용되는 표준임.

## 1. 핵심 설계 원칙
- **[MUST] Use Built-in Artifact:** 계획서는 반드시 에이전트의 내장 `implementation_plan.md` 아티팩트를 사용하여 작성할 것.
- **[MUST] Strict Structure:** 작성 시 관측성 도메인에 특화된 아래 10개 목차를 한국어 제목으로 100% 준수하여 명시할 것.
  1. 프로젝트 요약 (Executive Summary)
  2. 메트릭 아키텍처 및 파이프라인 (Metrics Architecture) & ADR
  3. 로그 파이프라인 및 스토리지 보존 전략 (Log Pipeline & Retention)
  4. 분산 추적 아키텍처 (Distributed Tracing Architecture)
  5. 데이터 보안 및 PII 마스킹 (Security & Data Masking)
  6. 대시보드 및 시각화 설계 (Dashboard & Visualization)
  7. 알람 룰 및 SLO/에러 버짓 (Alerting & SLO/Error Budget)
  8. 스토리지 비용 최적화 (FinOps & Storage Cost Estimation)
  9. 구현 청사진 (Implementation Blueprint)
  10. 자동화 검증 (Eval-Driven Testing)

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 아키텍처 설계 기획 표준
- **[PREFER] Agentic RAG:** 설계 전 에이전트 스스로 파일 검색·조회로 사내 표준 프롬프트 룰을 능동 조사하여 반영할 것.
- **[MUST] Environment Foraging:** 설계 착수 전 반드시 터미널에서 `kubectl get pods -n observability` 등 현재 모니터링 환경의 실제 상태를 팩트 기반으로 확보할 것.
- **[MUST] Stack Alternatives Table:** 메트릭/로그/트레이스 백엔드 스토리지 선택 시 2~3개의 서비스 대안(예: Prometheus vs Datadog vs CloudWatch 등)과 비용/운영 복잡도를 Markdown Table로 제시하여 의사결정을 유도할 것.
- **[MUST] Architecture Blueprint & ADR:** 도입된 기술에 대해 ADR 형식을 차용하여 명시적인 채택/기각 사유와 트레이드오프를 기록할 것.
- **[PREFER] Step-by-Step Execution:** 구현 청사진 설계 시 복잡도를 낮추기 위해 `Metrics` -> `Logs` -> `Traces` -> `Dashboards` 순으로 의존성을 분리하여 순차적 생성 흐름을 작성할 것.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- 구현 청사진: "로그 파이프라인은 Fluent Bit을 DaemonSet으로 배포하여 중앙 집중형 ElasticSearch 클러스터로 전송함. 보존 주기는 30일로 설정함."
- AI 제약사항: "- **[MUST] PII Masking First**: 모든 파이프라인의 엣지 단계(수집기)에서 주민번호, 이메일 등 민감 데이터를 반드시 마스킹 처리할 것."
</example>
<example>
[Bad]
- 모호한 청사진: "로그 수집기와 메트릭 서버를 환경 변수를 적당히 써서 알아서 설치하시오."
- 모호한 제약사항: "개인정보 안 새나가게 조심할 것."
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 작성된 계획서가 `implementation_plan.md` 규격에 정확히 들어맞으며, 마크다운 렌더링에 린트 에러가 없어야 합니다.
- **[MUST] 검증 도구 매핑:** 지정된 린터 도구 또는 `pre-flight-check.sh`로 일괄 검증할 것. (이유: 구문 검증 강제)

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Before Finalizing Plan] 점검 기준:**
  - 기준 1 (보안 및 비용 설계): PII 마스킹 처리(Security)와 스토리지 로그 보존 주기(FinOps)가 타당한 ADR 근거와 함께 보완적으로 설계되었는가?
  - 기준 2 (의존성 무결성): `메트릭 서버` -> `로그 수집기(DaemonSet)` -> `시각화 대시보드` 등 종속성이 해결된 순서로 구현 청사진이 기재되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 설계 중 예상되는 로그 인입량(Ingestion Rate)이나 메트릭 스크래핑 크기가 현재 할당된 클라우드 예산이나 스토리지 Quota를 명백히 초과할 것으로 감지되면, 즉시 **데이터 샘플링(Sampling) 아키텍처**를 추가로 설계하거나 작업을 멈추고 사용자에게 아키텍처 리스크를 정식 보고할 것.

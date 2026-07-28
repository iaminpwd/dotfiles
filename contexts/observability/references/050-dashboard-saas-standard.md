---
role: Senior SRE / Observability Engineer
priority: high
trigger: Apply these rules ONLY when designing Grafana dashboards or integrating observability SaaS platforms (Datadog, New Relic, Grafana Cloud).
references:
  - contexts/observability/references/010-observability-core.md
  - contexts/observability/references/020-metrics-alerting-standard.md
---
# 대시보드 및 SaaS 통합 표준

본 모듈은 Grafana 대시보드 설계 및 Datadog/New Relic 등 관측성 SaaS 플랫폼 연동 시 적용되는 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Dashboard as Code:** 대시보드는 UI에서 수동으로 클릭하여 만들지 말고, JSON/Jsonnet(grafonnet) 또는 Terraform Provider로 코드화하여 버전 관리하십시오.
- **[PREFER] Ingestion Cost Awareness:** SaaS 관측성 플랫폼은 수집 볼륨/카디널리티 기준으로 과금되므로, 대시보드·알람 설계 시 수집 볼륨과 카디널리티 증가분을 산정하여 예상 과금 영향을 함께 제시하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 대시보드 설계
- **[MUST] Golden Signal Top Row:** 서비스 대시보드 최상단에는 반드시 RED(Rate/Errors/Duration) 골든 시그널 패널을 배치하고, 세부 인프라 지표는 하단에 배치하십시오.
- **[MUST] Consistent Variable Naming:** 대시보드 템플릿 변수(`$namespace`, `$service` 등)는 모든 대시보드에서 동일한 명명 규칙을 사용하여, 대시보드 간 드릴다운(Drill-down) 링크가 정상 작동하도록 하십시오.
- **[PREFER] Provisioning as Code:** Grafana는 `provisioning/dashboards`, `provisioning/datasources` 디렉토리를 Git으로 관리하여 재기동 시 대시보드가 자동 복원되도록 하십시오.

### 2.2 SaaS 비용 및 카디널리티 통제
- **[MUST] Metric Allowlist:** Datadog/New Relic 등 종량제 SaaS로 전송하는 커스텀 메트릭은 명시적 허용목록(Allowlist)에 등록된 것만 전송하십시오.
- **[PREFER] Log-Based Metric Preference for High Cardinality:** 카디널리티가 높은 차원(사용자별, 요청별)은 시계열 메트릭 대신 로그 기반 집계(Log-based Metrics)나 샘플링된 이벤트로 대체하여 과금 폭증을 방지하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
```json
{
  "title": "Payment API - Golden Signals",
  "panels": [
    {"title": "Request Rate", "gridPos": {"y": 0}},
    {"title": "Error Rate", "gridPos": {"y": 0}},
    {"title": "P99 Duration", "gridPos": {"y": 0}}
  ],
  "templating": {"list": [{"name": "namespace"}, {"name": "service"}]}
}
```
</example>
<example>
[Bad]
- Grafana UI에서 수동으로 패널을 드래그해 만든 뒤 버전 관리 없이 방치 (재현 불가, 리뷰 불가)
- 모든 애플리케이션 커스텀 메트릭을 허용목록 없이 SaaS로 전량 전송 (예상치 못한 청구 폭증)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 대시보드 JSON이 스키마 오류 없이 프로비저닝되고, SaaS 전송 메트릭이 허용목록 범위 내로 확인되어야 합니다.
- **[MUST] 검증 도구 매핑:** `jq empty <dashboard.json>`으로 JSON 구조 유효성을 검증하고, Datadog/New Relic API의 사용량 조회 엔드포인트로 실제 수집 볼륨을 팩트로 확인하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Dashboard or SaaS Integration Proposed] 점검 기준 (절차는 010-observability-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (코드화): 대시보드가 버전 관리되는 코드로 존재하며 재현 가능한가?
  - 기준 2 (비용 통제): SaaS 전송 메트릭/로그가 허용목록 또는 샘플링으로 카디널리티 폭증이 통제되는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 허용목록 없이 고카디널리티 커스텀 메트릭을 SaaS로 전량 전송하는 설계가 감지되면 즉시 작업을 중단(Halt & Clarify)하고 필터링 적용을 요구하십시오.
  - 버전 관리되지 않는 수동 생성 대시보드가 프로덕션 유일한 관측 수단으로 방치된 경우 작업을 멈추고 Dashboard as Code로 전환을 요구하십시오.

---
role: Senior SRE / Observability Engineer
priority: high
trigger: Apply these rules ONLY when designing metrics, Alerting Rules, or PromQL/CloudWatch/Azure Monitor queries.
references:
  - contexts/observability/references/010-observability-core.md
---
# 메트릭 및 알람 설계 표준

해당 도메인 설계 및 작업 시 적용되는 표준임.

## 1. 핵심 설계 원칙
- **[MUST] RED & USE Methods:** 마이크로서비스는 RED(Rate, Errors, Duration), 인프라/노드는 USE(Utilization, Saturation, Errors) 지표 체계를 적용할 것.
- **[MUST] Actionable Alerts Only:** 사람이 즉시 취할 조치가 없는 알람(정보성 알람)은 Critical/Warning 채널이 아닌 별도 대시보드로 격리할 것.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 카디널리티 및 쿼리 설계
- **[MUST] High Cardinality Control:** 메트릭 레이블은 `response_code`, `method`, `route` 등 카디널리티가 명확히 통제 가능한 범주형 값만 채택할 것.
- **[MUST] Burn Rate Alerting:** 단순 임계치 알람 대신, Error Budget 소진 속도(Burn Rate)를 단기(1h)/장기(6h) 윈도우로 동시 관측하여 오탐과 지연 탐지를 모두 예방할 것.

### 2.2 알람 라우팅 및 알람 최적화
- **[MUST] Tiered Routing:** Critical(즉시 대응)과 Warning(다음 근무일 검토) 알람의 라우팅 채널(PagerDuty vs Slack 등)을 엄격히 분리할 것.
- **[MUST] Runbook Link Mandatory:** 모든 Critical 알람에는 대응 런북(Runbook) URL을 `annotations`에 필수 포함할 것.
- **[PREFER] Suppress Known Noise:** 정기 배치 작업이나 배포 시점의 예측 가능한 스파이크는 `for:` 지속 시간 조정 또는 억제(Silence) 규칙을 적용하여 오탐을 발생을 원천적으로 예방할 것.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
```yaml
groups:
- name: payment-api-burn-rate
  rules:
  - alert: PaymentAPIErrorBudgetBurnFast
    expr: |
      sum(rate(http_requests_total{job="payment-api",code=~"5.."}[5m]))
      / sum(rate(http_requests_total{job="payment-api"}[5m])) > (14.4 * 0.001)
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Payment API error budget burning fast"
      runbook_url: "https://runbooks.internal/payment-api-5xx"
```
</example>
<example>
[Bad]
```yaml
  - alert: HighCPU
    expr: node_cpu_seconds_total > 80
    # 사용자 체감과 무관한 인프라 지표, 런북 없음, severity 없음
```
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** Alerting Rule이 PromQL/쿼리 문법 오류 없이 검증되고, 모든 Critical 알람에 런북 링크가 포함되어야 합니다.
## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Alerting Rule Authored] 점검 기준 (절차는 010-observability-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (알람 최적화): 정상 스파이크(배치/배포)로 인한 오탐이 억제되었는가?
  - 기준 2 (조치 가능성): 알람에 런북 링크와 명확한 severity 라우팅이 포함되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - Alerting Rule에 `user_id`/`client_ip` 등 통제되지 않은 고유값이 레이블로 바인딩된 패턴이 감지되면 즉시 작업을 중단(Halt & Clarify)하고 레이블 설계를 수정할 것.
  - Critical 등급 알람에 런북 URL이 누락된 상태로 배포가 시도되면 작업을 멈추고 런북 링크 추가를 요구할 것.

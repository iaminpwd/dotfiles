---
role: Senior K8s Platform Architect
priority: high
trigger: Apply these rules ONLY when designing observability, monitoring, logging, or incident response architectures.
references:
  - contexts/k8s/references/010-k8s-core.md
---
# 컨텍스트 모듈: Enterprise Kubernetes 관측성(Observability) 및 SRE 표준

본 모듈은 Kubernetes 클러스터 모니터링, 로그 수집 아키텍처, 분산 추적 및 SRE 경보 시스템 설계 시 적용되는 기술 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] 3 Pillars of Observability:** 시스템 진단과 분석이 가능하도록 관측성(Metrics, Logs, Traces)의 3대 요소를 포괄하는 통합 파이프라인을 설계하십시오.
- **[MUST] SRE Practices (SLI/SLO):** 인프라 메트릭(CPU/Memory) 알람을 배제하고, 사용자 체감 성능을 반영한 SLO 위반 및 Error Budget Burn Rate에 기반한 알람 정책(Prometheus Alerting Rule)을 기본 구성하십시오.
- **[MUST] Prometheus Operator & CRD:** 레거시 annotation 수집 방식을 폐기하고, `ServiceMonitor`, `PodMonitor`, `PrometheusRule` CRD를 사용하여 수집 타겟을 정의하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 Metrics 및 구조화 로그 수집 규칙
- **[MUST] High Cardinality Control:** Prometheus TSDB의 OOM을 유발하는 고유 식별자(예: `user_id`, `client_ip`)를 레이블(Label)로 매핑하는 설계를 배제하고, 카디널리티가 제한된 범주형 변수(예: `response_code`, `method`)만 레이블로 사용하십시오.
- **[MUST] RED & USE Methods:** 마이크로서비스 관측에는 RED (Rate, Errors, Duration) 지표를, 노드/클러스터 인프라 관측에는 USE (Utilization, Saturation, Errors) 지표를 적용하십시오.
- **[MUST] Standard Output & JSON:** 컨테이너 로그는 stdout/stderr로 배출되게 하고, 파싱 비용 절감을 위해 JSON 포맷의 구조화 로깅을 적용하십시오.
- **[MUST] Context Enrichment & Masking:** 로그 라인에 네임스페이스 및 파드 메타데이터를 자동 주입하고, 전송 전 단계에서 민감 데이터(PII, 토큰 등)를 정규식 기반으로 자동 마스킹하는 보안 필터를 구성하십시오.

### 2.2 분산 추적 (Distributed Tracing) 및 경보
- **[MUST] OpenTelemetry (OTel) Standard:** 벤더 종속적 APM 에이전트 대신, 오픈 표준인 OpenTelemetry SDK 및 Collector 기반의 중립적 아키텍처를 도입하십시오.
- **[MUST] Context Propagation:** 서비스 간 호출 시 추적 정보(W3C `traceparent` 헤더)의 연속성을 보장하도록 컨텍스트 전파(Propagation)를 강제하십시오.
- **[MUST] Actionable & Tiered Alerts:** 경보(Alertmanager) 설정 시, 런북(Runbook) URL과 구체적 조치 방법을 명시하고 경고(Warning)와 치명(Critical) 라우팅 채널을 엄격히 분리하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- ServiceMonitor CRD 수집 설정:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: payment-api-monitor
  namespace: prod-payment
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: payment-api
  endpoints:
  - port: web
    path: /metrics
    interval: 15s
```
</example>
<example>
[Bad]
- `prometheus.io/scrape: "true"` 어노테이션 임의 기입 (자동화 감사 및 SSOT 통제 파괴)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** `ServiceMonitor` 설정에 에러가 없고, 로그 마스킹 정규식 린트가 통과되며, Alerting Rule이 PromQL 형식에 유효하게 검증되어야 합니다.
- **[MUST] 검증 도구 매핑:** `promtool check rules <alert_file>` 및 `kube-linter`를 활용해 모니터링 매니페스트 설정을 정적 검증하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Metric Validation] 도메인 자가 채점:** 모니터링 알람 설정을 제안하거나 수정한 직후, 스스로 `<self_critique>` 태그를 열어 아래 2가지 기준으로 1~5점 자가 채점을 수행하고 사유를 명시하십시오. (두 기준 모두 5점 만점일 때만 작업을 완료하십시오)
  - 기준 1 (피로도 방지): 시스템 정상 기동이나 정기 배치 작업 시 오탐 알람이 발생할 리스크가 완전히 통제되었는가?
  - 기준 2 (사각지대 제거): 핵심 비즈니스 에러 버짓(Burn Rate) 상태를 실시간 탐지하는 가시성이 확보되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - PromQL 쿼리 레이블이나 애플리케이션 계측 코드에 `user_id`나 `client_ip` 같은 무제한 고유 값이 레이블 키로 바인딩되는 패턴이 감지될 시 즉시 작업을 중단(Halt & Clarify)하고 키 설정을 필터링하십시오.
  - 로그 파이프라인 매니페스트(Fluent Bit / Promtail 등) 상에 외부 시크릿 유출을 방지하기 위한 마스킹 필터(`filter` regex) 설정이 누락되어 있음이 발견될 시 즉시 작업을 멈추고 보안 룰을 주입하십시오.

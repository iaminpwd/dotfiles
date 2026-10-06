---
trigger: Apply these rules ONLY when configuring Prometheus Operator CRDs (ServiceMonitor, PodMonitor, PrometheusRule) inside a Kubernetes cluster.
references:
  - contexts/k8s/references/010-k8s-core.md
  - contexts/observability/SKILL.md
---
# 컨텍스트 모듈: Kubernetes Prometheus Operator 수집 표준

본 모듈은 K8s 클러스터 내부의 Prometheus Operator CRD 기반 메트릭 수집 문법에만 집중하는 K8s 고유 표준임. SLI/SLO, RED/USE, 카디널리티, 구조화 로깅, 분산 추적 등 클라우드/K8s 공통 관측성 원칙은 `observability` 스킬(`observability 스킬(SKILL.md)`)을 참조할 것.

## 1. 핵심 설계 원칙
- **[MUST] Observability Delegation:** SLI/SLO, 알람 설계, 로깅, 분산 추적 등 관측성 일반 원칙은 `observability` 스킬로 검증을 위임하고, 본 모듈은 K8s 네이티브 CRD 문법만 다루십시오.
- **[MUST] Prometheus Operator & CRD:** 레거시 `prometheus.io/scrape` 어노테이션 수집 방식을 폐기하고, `ServiceMonitor`, `PodMonitor`, `PrometheusRule` CRD로 수집 타겟을 선언적으로 정의할 것.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 K8s 네이티브 수집 및 로그 메타데이터
- **[MUST] CRD-Based Target Discovery:** `ServiceMonitor`/`PodMonitor`의 `selector.matchLabels`를 서비스/파드의 `app.kubernetes.io/name` 표준 레이블과 일치시켜 수집 대상을 명시적으로 한정할 것.
- **[MUST] stdout/stderr Only:** 컨테이너 로그는 stdout/stderr로만 출력할 것. kubelet의 로그 수집 경로(`/var/log/containers`)는 파일 기반 로깅을 인식하지 못함.
- **[MUST] K8s Metadata Enrichment:** 로그 수집 에이전트(Fluent Bit 등)가 네임스페이스, 파드명, 컨테이너명을 자동 주입하도록 구성할 것.

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
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** `ServiceMonitor`/`PrometheusRule` CRD가 문법 오류 없이 대상 서비스를 정확히 스크래핑해야 합니다.

## 4. 변경 전 확인과 실행 경계
- **[MUST] 중단 조건 (Halt Conditions):**
  - `prometheus.io/scrape` 어노테이션 기반의 레거시 수집 방식이 신규로 추가되는 패턴이 감지되면 즉시 작업을 중단(Halt & Clarify)하고 CRD 방식으로 전환을 요구할 것.

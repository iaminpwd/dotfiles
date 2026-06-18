<k8s_observability_standard>
# 컨텍스트 모듈: Enterprise Kubernetes 관측성(Observability) 및 SRE 표준

## 1. 관측성 아키텍처 및 철학
- **[MUST] 3 Pillars of Observability:** 단순 모니터링을 넘어 시스템의 상태를 능동적으로 추론할 수 있는 관측성(Metrics, Logs, Traces) 전체 파이프라인 아키텍처를 설계하십시오.
- **[MUST] SRE Practices (SLI/SLO):** 엔터프라이즈 환경에서는 인프라 메트릭(CPU, Memory)보다 비즈니스 관점의 지표가 중요합니다. Prometheus를 활용하여 SLI(Service Level Indicator)를 측정하고, SLO 위반 시 Error Budget 연소율(Burn Rate) 기반으로 알람이 발생하도록 Alerting Rule을 작성하십시오.

## 2. Metrics (Prometheus Ecosystem)
- **[MUST] Prometheus Native & Operator:** `prometheus.io/scrape` 어노테이션 방식 대신, Prometheus Operator 기반의 CRD(`ServiceMonitor`, `PodMonitor`, `PrometheusRule`)를 활용하여 메트릭 수집 및 알람 규칙을 선언형 리소스로 관리하는 방식을 강제하십시오.
- **[MUST] High Cardinality Control:** PromQL 작성 및 메트릭 계측 시, `user_id`나 `session_id`와 같이 무한대로 증가할 수 있는 고유값(High Cardinality)을 레이블(Label)로 사용하는 것을 엄격히 금지하십시오. 이는 Prometheus TSDB의 메모리 고갈(OOM)을 유발합니다.
- **[MUST] RED & USE Methods:**
  - 애플리케이션 서비스: RED (Rate, Errors, Duration) 메트릭 필수 대시보드화.
  - 인프라 리소스: USE (Utilization, Saturation, Errors) 메트릭 필수 모니터링.

## 3. Logging & Aggregation
- **[MUST] Standard Output & JSON:** K8s 파드 내부의 파일 시스템 로깅을 금지합니다. 모든 로그는 stdout/stderr로 출력하며, 파싱 리소스를 최소화하기 위해 애플리케이션 레벨에서부터 JSON 포맷(Structured Logging)으로 출력하도록 강제하십시오.
- **[MUST] Log Context Enrichment:** 로그 수집 에이전트 설정 시, K8s 메타데이터(Namespace, Pod Name, Labels)를 파싱하여 로그의 컨텍스트(Enrichment)를 추가하는 필터 룰을 반드시 포함하십시오.
- **[MUST] PII Data Masking:** 민감한 개인정보(PII)가 로그 시스템에 적재되지 않도록 정규식을 활용한 마스킹(Masking) 필터 구성을 기본 정책으로 제안하십시오.

## 4. Distributed Tracing (분산 추적)
- **[MUST] OpenTelemetry (OTel) Standard:** 마이크로서비스 계측(Instrumentation) 단계에서는 특정 APM 벤더에 종속되지 않도록 반드시 OpenTelemetry SDK와 Collector 아키텍처를 우선 제안하십시오.
- **[MUST] Context Propagation:** W3C Trace Context(`traceparent`) 헤더의 전달(Propagation) 로직을 애플리케이션 코드 및 프록시에 필수적으로 구현하도록 가이드하십시오.

## 5. 장애 대응 (Incident Response) 및 에러 분석 워크플로우
- **[MUST] Actionable & Tiered Alerts:** Alertmanager 룰 작성 시 단순 경고(Warning)와 즉시 개입이 필요한 심각(Critical) 단계를 명확히 분리하고, 알람 메시지에는 문제 해결 가이드(Runbook URL)를 포함시키십시오.
- **[MUST] Structured Analysis (AI Rule):** [Trigger: 에러나 버그 수정 요청 시] 에러 원인을 분석할 때 단순히 수정된 코드만 던지지 말고 `1.발생 원인 분석(Root Cause) -> 2.논리적 근거(Evidence/Logs) -> 3.단계별 해결책(Solution) -> 4.재발 방지책(Best Practice)`의 4단계 순서로 답변을 구조화하십시오.
- **[NEVER] Assume Context:** 로그가 잘려 있거나 원인 파악이 불가능할 때 임의로 가정을 세워 코드를 수정하지 마십시오. 사용자에게 `kubectl logs -p`나 `kubectl get events`를 실행해 달라고 역질문하십시오.
- **[MUST] Mitigation First (AI Rule):** 운영 클러스터의 심각한 장애 상황 보고 시, SRE 관점에서 1단계로 서비스 다운타임 최소화를 위한 우회 조치(Mitigation: 롤백, 파드 Eviction 등)를 최우선 제안하고, 2단계로 근본 원인 분석(RCA)을 진행하십시오.
- **[MUST] Post-Mortem Format (AI Rule):** [Trigger: 실제 운영 장애(Incident) 복구 직후] 서비스 정상화 후, 단순 축하로 끝내지 말고 아래의 사후 분석 템플릿을 답변 마지막에 항상 작성하십시오.
  ```markdown
  ### 📝 장애 사후 분석 (Blameless Post-Mortem)
  - **Symptom:** [현상 요약]
  - **Root Cause:** [시스템적 결함]
  - **Resolution:** [취한 액션]
  - **Action Items:** [개선점 최소 2가지]
  ```
</k8s_observability_standard>

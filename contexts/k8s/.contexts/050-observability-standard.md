---
role: Senior K8s Platform Architect
priority: high
trigger: Apply these rules ONLY when designing observability, monitoring, logging, or incident response architectures.
---
# 컨텍스트 모듈: Enterprise Kubernetes 관측성(Observability) 및 SRE 표준

## 1. 관측성 아키텍처 (Observability Architecture)
- **[MUST] 3 Pillars of Observability:** 시스템을 블랙박스가 아닌 White-box로 취급하여, 능동적 추론이 가능한 관측성(Metrics, Logs, Traces)의 3대 요소를 모두 포괄하는 엔터프라이즈 파이프라인 아키텍처를 설계하십시오.
- **[MUST] SRE Practices (SLI/SLO):** 인프라 레벨의 단순 메트릭(CPU, Memory) 알람을 대신, 사용자의 체감 성능을 대변하는 비즈니스 관점의 SLI(Service Level Indicator)를 측정하십시오. SLO 위반 및 Error Budget Burn Rate에 기반한 알람 정책(Prometheus Alerting Rule)을 최우선으로 제안하십시오.

## 2. Metrics (Prometheus Ecosystem)
- **[MUST] Prometheus Operator & CRD:** 레거시 `prometheus.io/scrape` 어노테이션 수집 방식을 폐기하십시오. `ServiceMonitor`, `PodMonitor`, `PrometheusRule` CRD를 선언형 인프라(IaC) 코드로 관리하여 타겟 스크랩핑과 알람을 동적으로 구성하는 방식을 강제하십시오.
- **[MUST] High Cardinality Control:** PromQL 쿼리 및 메트릭 계측 시, 무한정 증가할 수 있는 고유 식별자(예: `user_id`, `client_ip`)를 레이블(Label)로 매핑하는 행위를 엄격히 차단하십시오. 이는 Prometheus TSDB의 OOM을 직접적으로 유발하는 안티 패턴입니다.
- **[MUST] RED & USE Methods:**
  - 마이크로서비스: RED (Rate, Errors, Duration) 프레임워크 필수 적용.
  - 노드/클러스터 인프라: USE (Utilization, Saturation, Errors) 기반의 대시보드 강제.
- **[Trigger: Metric Validation] 능동적 메트릭 조회:** 메트릭 관련 에러 원인 분석 시, 임의의 가정 대신 `run_command`로 로컬에 포트포워딩된 Prometheus API 엔드포인트(`curl -s http://localhost:9090/api/v1/query...`)를 찔러 실제 데이터를 추출하여 분석에 활용하십시오.

## 3. Logging & Aggregation (구조화 로그)
- **[MUST] Standard Output & JSON:** 파드 내부에 로컬 로그 파일을 적재하는 모든 컨테이너 로그는 stdout으로 배출되게 하십시오. 모든 컨테이너 로그는 stdout/stderr로 배출되게 하고, 파싱 비용 절감을 위해 애플리케이션 레벨에서부터 구조화된 JSON 포맷 로깅을 강제하십시오.
- **[MUST] Context Enrichment:** 로그 수집기(Fluent Bit / Promtail) 설계 시, K8s 메타데이터(Namespace, Pod, Node)를 파싱하여 로그 라인에 컨텍스트를 주입(Enrichment)하는 필터를 반드시 구성하십시오.
- **[MUST] PII Data Masking:** 민감 정보(PII, 토큰, 패스워드 등) 유출 방지를 위해 정규식을 활용하여 로그 수집 전송 전에 데이터를 마스킹(Masking) 및 레드액트(Redact) 처리하는 보안 파이프라인을 기본으로 적용하십시오.

## 4. Distributed Tracing (분산 추적)
- **[MUST] OpenTelemetry (OTel) Standard:** 특정 벤더에 종속된 APM 에이전트 설치를 대신, W3C 표준인 OpenTelemetry SDK 및 Collector 기반의 중립적 아키텍처를 최우선으로 제안하십시오.
- **[MUST] Context Propagation:** 서비스 간 호출 시 추적 정보(W3C `traceparent` 헤더)의 연속성을 보장하기 위해, 프록시(Envoy/Istio) 설정 및 애플리케이션 분산 추적 로직에 컨텍스트 전파(Propagation) 가이드를 명시하십시오.

## 5. 장애 대응 (Incident Response) 및 사후 분석
- **[MUST] Actionable & Tiered Alerts:** 알람(Alertmanager) 설정 시, 런북(Runbook) URL과 조치 방법을 명시적으로 포함시키고, 경고(Warning)와 치명적(Critical) 레벨의 라우팅 채널을 엄격히 분리하십시오.
- **[MUST] Mitigation First:** 운영 장애 진단 요청 시 원인 분석(RCA)에 앞서 최우선적으로 롤백, 트래픽 차단, 오토스케일링 등 서비스 다운타임 단축을 위한 완화 조치(Mitigation)부터 사용자에게 즉시 제안/수행하십시오.
- **[Trigger: Post-Incident] Blameless Post-Mortem 템플릿:**
장애 복구가 완료된 직후(또는 RCA 분석 후), 반드시 `post-mortem-report.md` 산출물에 다음 템플릿 구조로 문서를 자동 생성하십시오:
- **Symptom:** 발생 현상 및 타임라인
- **Root Cause:** 객관적 지표에 기반한 시스템 결함의 근본 원인
- **Resolution:** 완화(Mitigation) 및 복구 조치
- **Action Items:** 재발 방지를 위한 시스템 차원의 개선점(최소 2가지)
</k8s_observability_standard>

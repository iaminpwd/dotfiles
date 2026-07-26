---
role: Senior SRE / Observability Engineer
priority: high
trigger: Apply these rules ONLY when instrumenting distributed tracing or configuring OpenTelemetry Collectors.
references:
  - contexts/observability/references/010-observability-core.md
reviewed: 2026-07-21
---
# 분산 추적 (Distributed Tracing) 표준

본 모듈은 OpenTelemetry 기반 분산 추적 계측 및 컨텍스트 전파 설계 시 적용되는 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] End-to-End Context Propagation:** 서비스 간 호출(HTTP, gRPC, 메시지 큐) 전 구간에서 W3C `traceparent` 헤더 전파가 끊기지 않도록 설계하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 계측 및 샘플링
- **[MUST] Auto-Instrumentation First:** 언어별 OpenTelemetry Auto-Instrumentation Agent를 우선 적용하고, 커스텀 Span은 비즈니스적으로 의미 있는 경계(결제 처리, 외부 API 호출 등)에만 수동 추가하십시오.
- **[MUST] Tail-Based Sampling for Errors:** Head-based 샘플링만 적용할 경우 에러 트레이스가 누락될 수 있으므로, Collector 단에서 에러/고지연 트레이스를 100% 보존하는 Tail-Based Sampling 정책을 구성하십시오.
- **[PREFER] Sampling Rate by Traffic Tier:** 트래픽이 큰 서비스는 기본 샘플링율(예: 10%)을 적용하고, 저트래픽 핵심 경로는 100% 샘플링을 유지하십시오.

### 2.2 Collector 아키텍처
- **[MUST] Collector as Gateway:** 애플리케이션이 백엔드(Datadog, Grafana Tempo 등)로 직접 전송하지 말고, OpenTelemetry Collector를 게이트웨이로 경유시켜 백엔드 교체 시 애플리케이션 재배포 없이 Exporter 설정만 변경 가능하도록 하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
```yaml
processors:
  tail_sampling:
    policies:
      - name: errors-always-sample
        type: status_code
        status_code: {status_codes: [ERROR]}
      - name: default-sample
        type: probabilistic
        probabilistic: {sampling_percentage: 10}
```
</example>
<example>
[Bad]
```yaml
# Head-based 확률 샘플링만 10% 적용 -> 희귀 에러 트레이스가 통계적으로 누락됨
```
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 서비스 간 호출 체인에서 단일 `trace_id`로 전체 요청 흐름이 끊김 없이 조회되어야 합니다.
- **[MUST] 검증 도구 매핑:** OpenTelemetry Collector 설정 변경 시 `otelcol validate --config <file>`(Collector Contrib 배포판 기준)로 설정 문법을 검증하고, 실제 트레이스 백엔드(Grafana Tempo/Jaeger UI 등)에서 임의 요청의 `trace_id`로 전체 스팬이 조회되는지 팩트로 확인하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Tracing Instrumented] 점검 기준 (절차는 010-observability-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (전파 연속성): 서비스 간 호출 전 구간에서 트레이스 컨텍스트 전파가 끊기지 않는가?
  - 기준 2 (에러 가시성): 에러/고지연 트레이스가 샘플링에 의해 누락되지 않고 보존되는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 서비스 간 호출 경로 중 `traceparent` 헤더가 전파되지 않아 트레이스가 끊기는 구간이 감지되면 즉시 작업을 중단(Halt & Clarify)하고 계측 누락 구간을 보완하십시오.
  - Head-based 확률 샘플링만 적용되어 에러 트레이스 보존이 보장되지 않는 설계가 감지되면 작업을 멈추고 Tail-Based Sampling 도입을 요구하십시오.

---
trigger: Apply these rules when designing monitoring, logging, or tracing architecture across any cloud or K8s environment.
references:
  - contexts/observability/references/020-metrics-alerting-standard.md
---
# 관측성(Observability) 코어 표준

관측성 설계 시 적용되는 표준임.

## 1. 핵심 설계 원칙
- **[MUST] 3 Pillars Integration:** 메트릭(Metrics), 로그(Logs), 트레이스(Traces)를 서로 단절된 도구로 설계하는 대신, 공통 식별자(Trace ID, 서비스명, 네임스페이스 레이블)로 상호 연관(Correlation) 조회가 가능하도록 통합 설계할 것.
- **[PREFER] User-Centric SLI:** CPU/Memory 같은 인프라 메트릭이 아닌, 응답 지연(Latency)/에러율/가용성 등 사용자 체감 지표를 우선 SLI로 채택하여 수치화된 SLO를 반드시 제시할 것.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 SLO 및 에러 버짓
- **[MUST] Explicit SLO Target:** 새로운 서비스의 관측성을 설계할 때 반드시 구체적인 SLO 수치(예: "30일 롤링 윈도우 기준 P99 레이턴시 300ms 이하 99.9%")로 명시할 것.
- **[MUST] Error Budget Policy:** 에러 버짓이 소진되면 신규 기능 배포를 동결하고 안정화 작업을 우선하는 정책을 문서화할 것.

### 2.2 도구 중립성 및 벤더 독립성 보장
- **[PREFER] Vendor-Neutral Instrumentation:** 계측(Instrumentation) 코드는 특정 APM 벤더 SDK 대신 OpenTelemetry SDK를 반드시 우선 채택하여, 백엔드(Datadog, Grafana, CloudWatch 등) 교체 시 애플리케이션 코드 수정 없이 Exporter 설정만 변경 가능하도록 설계할 것.
- **[MUST] Cloud-Agnostic Correlation Keys:** AWS(X-Ray Trace ID), Azure(Operation ID), K8s(Pod/Namespace 레이블) 등 플랫폼별 상관관계 키를 로그/메트릭/트레이스 3곳 모두에 일관되게 주입할 것.

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] Delegation:** 현재 작업의 계획·메트릭·로그·추적·대시보드 기준만 각각 `005`, `020`, `030`, `040`, `050`에서 선택한다.

## 4. 변경 전 확인과 실행 경계
- **[PREFER] 공통 자가 비판 절차 (전 observability 모듈 SSOT):** 참조 모듈(005, 020, 030, 040, 050) 중 현재 작업의 기준만 확인한다. 전체 조회나 별도 자가비판 출력은 필요하지 않다.
- **[MUST] 중단 조건 (Halt Conditions):**
  - SLO 수치나 사용자 체감 지표 정의 없이 "안정적인 모니터링"처럼 모호한 목표로 설계를 진행하려는 시도가 감지되면 즉시 작업을 중단(Halt & Clarify)하고 구체적 수치를 요청할 것.

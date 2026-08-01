---
name: observability
description: |
  클라우드/K8s 전반의 관측성(Observability) 설계 스킬. 메트릭·로그·트레이스 3대 요소,
  SLI/SLO/에러 버짓, 알람 설계, 구조화 로깅, OpenTelemetry 분산 추적,
  Grafana/Datadog 등 대시보드 및 SaaS 통합.
---
# observability Skill

모니터링, 로깅, 분산 추적, 알람 설계 작업 시 발동됨. (장애 대응은 각 스킬의 `100-incident-response.md` 참조)

## 1. 작업 유형별 참조 문서 라우팅 (SSOT)

| 작업 유형 | 참조 문서 |
|---|---|
| 프로젝트 기획 및 아키텍처 설계 | references/005-project-planning-template.md |
| 관측성 기본 원칙, SLI/SLO, Error Budget | references/010-observability-core.md |
| 메트릭 설계 및 알람 (PromQL, CloudWatch, Azure Monitor) | references/020-metrics-alerting-standard.md |
| 구조화 로깅 및 로그 파이프라인 (Loki/ELK/CloudWatch Logs) | references/030-logging-standard.md |
| 분산 추적 (OpenTelemetry) | references/040-tracing-standard.md |
| 대시보드 설계 및 SaaS 연동 (Grafana, Datadog) | references/050-dashboard-saas-standard.md |

* **기본 관측성 코어 원칙**: references/010-observability-core.md

## 2. 작업 프로세스 제약 (Operational Gate)

- **[MUST] 사전 룰북 및 연관 참조 연쇄 분석 (Recursive Reference Check)**: 모니터링/로깅/추적 관련 코드나 설정(Alerting Rule, 대시보드 정의 등)을 작성하기 전, 반드시 라우팅 테이블에서 대상 룰북을 찾아 먼저 읽으십시오. 또한 해당 룰북 내에 명시된 연관 참조 문서(`references:` 항목 또는 텍스트 내 참조 문서)가 존재하는 경우 연쇄적으로 읽되, 이미 읽은 파일은 중복 방문하지 않는 방문 목록(Visited Set) 규칙을 준수하여 무한 루프 없이 연결된 모든 연관 룰북을 빠짐없이 수집할 것.

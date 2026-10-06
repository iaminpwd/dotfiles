---
name: observability
description: |
  클라우드/K8s 전반의 관측성(Observability) 설계 스킬. 메트릭·로그·트레이스 3대 요소,
  SLI/SLO/에러 버짓, 알람 설계, 구조화 로깅, OpenTelemetry 분산 추적,
  Grafana/Datadog 등 대시보드 및 SaaS 통합.
---
# observability Skill

관측성 작업에 사용한다. 일반 SLI/SLO·로깅·트레이싱·대시보드 설계 지식은 현재 코드와 공식 문서를 기준으로 판단하고, 이 저장소가 실제로 강제하는 검증 계약만 아래에 둔다.

## 저장소 검증 계약

- PrometheusRule/알람 검증 로직을 변경하면 `bash contexts/observability/tests/run.sh`를 실행한다.
- 실제 검증기는 `contexts/observability/scripts/validate-alert-rules.sh`, 커밋 시점 배선은 `bin/hooks/plugins/observability-check.sh`다.
- Critical 알람은 `annotations.runbook_url`이 필요하고, `user_id`·`client_ip` 같은 고카디널리티 레이블은 차단한다.
- YAML 파싱 실패·잘못된 `groups` 구조를 규칙 0건으로 오인해 통과시키지 않는다. 멀티 도큐먼트에서는 PrometheusRule 문서를 정확히 골라 정책을 검사한다.
- 검증에 필요한 `yq`가 없으면 회귀 테스트는 실패한다. 다중 문서 입력도 파일당 `yq` 변환을 반복하지 않는 배치 계약을 유지한다.
- 실제 변경 파일의 quick/full 검사와 WARNING/SKIP 해석은 `contexts/pre-flight-check/SKILL.md`를 따른다.

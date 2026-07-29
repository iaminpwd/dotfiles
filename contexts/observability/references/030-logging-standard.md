---
role: Senior SRE / Observability Engineer
priority: high
trigger: Apply these rules ONLY when designing structured logging, log aggregation pipelines, or log retention policies.
references:
  - contexts/observability/references/010-observability-core.md
---
# 구조화 로깅 및 로그 파이프라인 표준

해당 도메인 설계 및 작업 시 적용되는 표준임.

## 1. 핵심 설계 원칙
- **[MUST] Structured JSON Logging:** 모든 애플리케이션 로그는 stdout/stderr로 JSON 구조화 포맷으로만 출력할 것.
- **[MUST] PII Masking at Source:** 개인정보(PII)나 시크릿은 로그 파이프라인 전송 전 단계(애플리케이션 또는 수집 에이전트)에서 마스킹할 것.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 로그 구조 및 컨텍스트
- **[MUST] Context Enrichment:** 로그 라인에 `trace_id`, `service.name`, `namespace`, `severity` 필드를 표준 스키마로 자동 주입할 것.

### 2.2 비용 및 보존 정책
- **[PREFER] Retention Tiering:** 실시간 조회가 필요한 최근 로그(예: 7~14일)는 고속 조회 계층(Loki, CloudWatch Logs)에 보관하고, 장기 보관 로그는 반드시 저비용 오브젝트 스토리지(S3/Blob)로 분리하여 비용을 통제할 것.
- **[PREFER] Sampling for High-Volume Debug Logs:** `DEBUG` 레벨 로그가 대량 발생하는 경로는 100% 수집을 격리하고, 샘플링(예: 10%) 비율을 의무 적용하여 볼륨 팽창을 유지할 것.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
```json
{"timestamp":"2026-07-21T10:00:00Z","severity":"ERROR","service.name":"payment-api","trace_id":"4bf92f...","namespace":"prod-payment","message":"downstream timeout","user_id_hash":"a1b2***"}
```
</example>
<example>
[Bad]
```text
2026-07-21 10:00:00 ERROR payment failed for user john.doe@example.com card 4111111111111111
```
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 로그 출력이 JSON 스키마 검증을 통과하고, PII 마스킹 필터가 파이프라인에 구성되어야 합니다.
- **[MUST] 검증 도구 매핑:** `jq empty <logfile>`로 JSON 구조 유효성을 검증하고, `logcli query`(Loki 사용 시)로 실제 파이프라인에 마스킹이 적용된 로그가 도착하는지 팩트로 확인할 것.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Logging Pipeline Configured] 점검 기준 (절차는 010-observability-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (구조화): 모든 로그가 파싱 가능한 JSON 스키마를 따르는가?
  - 기준 2 (데이터 보호): PII/시크릿이 수집 이전 단계에서 마스킹되는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 로그 파이프라인에 이메일, 카드번호, 토큰 등 PII/시크릿 마스킹 필터가 누락된 상태가 감지되면 즉시 작업을 중단(Hard Block)하고 마스킹 규칙 추가를 요구할 것.
  - 자유 텍스트 로그 포맷이 신규 도입되어 구조화 로깅 원칙을 위반할 경우 작업을 멈추고 JSON 포맷으로 전환을 요구할 것.

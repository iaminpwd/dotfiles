---
role: Senior AIOps Engineer
priority: high
trigger: Apply these rules ONLY when writing automation scripts, testing edge-cases, or configuring error handling logic.
references:
  - contexts/aiops/references/010-aiops-core.md
  - contexts/aiops/references/060-agent-logic.md
---
# 컨텍스트 모듈: 시스템 탄력성 (Resiliency) 및 자동화 카오스 엔지니어링

본 모듈은 자동화 파이프라인 스크립팅, 분산 시스템의 예외 엣지 케이스 처리 및 카오스 엔지니어링을 통한 인프라 복원력 검증 시 적용되는 기술 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Idempotency:** 네트워크 지연으로 인한 중복 웹훅 인입 시 상태의 단일 변경을 보장하도록 DynamoDB나 Redis 기반의 Idempotency Key(멱등성 키) 패턴을 핵심 로직에 구현하십시오.
- **[MUST] Exponential Backoff & Circuit Breaker:** 외부 API(GitHub, PagerDuty 등) 호출 시 Rate Limit(429) 및 일시 장애에 대응하도록 지수적 백오프와 지터(Exponential Backoff & Jitter)를 적용하고, 장애 장기화 시 시스템 리소스 보호를 위한 서킷 브레이커(Circuit Breaker)를 결합하십시오.
- **[MUST] Prompt Injection Defense:** 에이전트가 클라우드 로그(CloudWatch, Azure Monitor Logs 등) 등 외부 텍스트를 파싱할 때, 로그 내에 포함된 악성 명령어에 노출되지 않도록 입력값을 철저히 소독(Sanitization)하고 시스템 프롬프트와 물리적으로 격리하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 엣지 케이스 및 이벤트 전처리
- **[MUST] Flapping Debounce & Rate Limiting:** 메트릭 임계치 부근에서 알람이 폭주하는 Flapping 현상을 방어하기 위해, 특정 시간 창(Time Window) 내 이벤트를 압축/디바운스(Debounce)하는 전처리 계층을 구현하십시오.
- **[MUST] Strict Grounding:** 장애 RCA 분석 시 AI 모델 자체의 파라미터 지식 의존을 배제하고, 수집된 팩트 데이터와 공식 런북에만 기반(Grounding)하여 답변하며, 입증할 수 없는 사실은 "알 수 없음"으로 처리하여 환각을 차단하십시오.

### 2.2 복원력 및 카오스 엔지니어링
- **[MUST] Fault Injection Testing:** 단위 테스트 작성 시 정상 경로 외에 네트워크 타임아웃, 권한 오류, 비정상 대형 페이로드를 의도적으로 주입하는 방어 로직 검증 코드(Fault Injection)를 필수 포함하십시오.
- **[PREFER] Chaos Engineering:** 프로덕션 인프라 복원력 검증을 위해 클라우드 네이티브 카오스 도구(AWS FIS, Azure Chaos Studio) 또는 오픈소스 도구(Chaos Mesh, LitmusChaos)를 연동하여 데이터베이스 Failover 및 가용 영역(AZ) 장애 상황을 주기적으로 자동 시뮬레이션하는 파이프라인을 구축하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- Redis 멱등성 락 획득:
```python
def process_webhook(event_id, payload):
    lock_acquired = redis_client.set(f"lock:event:{event_id}", "locked", ex=300, nx=True)
    if not lock_acquired:
        return "Duplicate Request Ignored"
    return execute_business_logic(payload)
```
</example>
<example>
[Bad]
- 멱등성 락 부재 (동일 결제 알람이 여러 번 유입될 시 중복 결제 사고 유발 안티패턴)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 멱등 키 검증 단위 테스트 및 지수 백오프 모킹 테스트가 에러 없이 성공하고, 모든 테스트 케이스의 코드 커버리지가 기준치를 상회해야 합니다.
- **[MUST] 검증 도구 매핑:** `pytest` 또는 `jest`를 실행하여 Fault Injection 및 에러 핸들링 코드가 정상적으로 예외를 캐치 및 격리하는지 이진(Pass/Fail) 결과를 검증하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Before Executing Critical Actions] 점검 기준 (절차는 010-aiops-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (멱등성 작동): 동일한 자동화 명령이 2회 연속 수행되더라도 상태 오염이나 중복 인프라 생성이 확실히 방지되는가?
  - 기준 2 (예외 처리): 연동 대상인 API 게이트웨이 및 외부 서비스 장애 시, 에러를 조기에 차단하고 시스템을 안정적으로 복구시키는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 배치/이벤트 처리 스크립트 작성 시, 중복 유입에 대응하기 위한 멱등성 검증 로직(Idempotency Key 등)이 누락되어 데이터 오염 위험이 확인될 시 작업을 즉시 중단(Halt & Clarify)하고 락 설정을 구현하십시오.
  - LLM 에이전트 인풋에 사용자 입력값 소독(Sanitization) 필터가 누락되어 프롬프트 인젝션 및 무단 시스템 탈옥 공격에 노출될 위험이 탐지될 경우 작업을 즉시 멈추고 보안 가이드를 작성하십시오.

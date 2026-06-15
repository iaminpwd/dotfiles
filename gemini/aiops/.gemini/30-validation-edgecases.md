# 시스템 탄력성 (Resiliency) 및 카오스 엔지니어링

## 1. 분산 시스템의 극한 엣지 케이스 방어
- **[MUST] Idempotency (멱등성):** 네트워크 지연이나 재시도(Retry)로 인해 동일한 알람/이벤트가 여러 번 유입되더라도, 중복 조치가 발생하지 않도록 Idempotency Key(멱등성 키) 패턴을 핵심 로직에 구현하십시오.
- **[MUST] Backoff & Circuit Breaker:** 외부 API(GitHub, PagerDuty 등) 호출 시 일시적 장애나 Rate Limit 초과에 대비해 Exponential Backoff & Jitter(지수적 백오프와 지터) 재시도 로직을 적용하고, 지속적 장애 시 시스템 연쇄 장애를 방지하는 서킷 브레이커(Circuit Breaker) 패턴을 적용하십시오.
- **[MUST] Flapping Debounce:** 인프라 매트릭이 임계치를 오르락내리락하며 알람이 폭주하는 Flapping 현상에 대비해, 특정 시간 창(Time Window) 내의 이벤트를 압축/디바운스(Debounce)하는 전처리 계층을 두십시오.

## 2. 장애 시뮬레이션 (Chaos Engineering)
- **[MUST] Fault Injection Testing:** 단순히 정상 동작 케이스만 테스트하는 코드는 프로덕션에 올릴 수 없습니다. 의도적으로 권한 오류(403), 타임아웃, 대규모 페이로드를 주입하는 카오스 엔지니어링(Fault Injection) 테스트 스크립트를 포함하여 방어 로직을 실증하십시오.

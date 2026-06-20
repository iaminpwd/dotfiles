<aiops_validation_edgecases>
# 컨텍스트 모듈: 시스템 탄력성 (Resiliency) 및 카오스 엔지니어링

## 1. 분산 시스템의 극한 엣지 케이스 방어 로직
- **[MUST] Idempotency (멱등성 보장):** 네트워크 지연이나 장애로 인해 동일한 알람/웹훅 이벤트가 파이프라인에 여러 번 유입되더라도 시스템 상태가 중복 변경되지 않도록, DynamoDB나 Redis 기반의 Idempotency Key(멱등성 키) 패턴을 핵심 처리 로직에 반드시 구현하십시오.
- **[MUST] Exponential Backoff & Circuit Breaker:** 외부 API(GitHub, PagerDuty, LLM 등) 호출 시 일시적 장애나 Rate Limit(429) 초과에 대비해 지수적 백오프와 지터(Exponential Backoff & Jitter) 로직을 적용하십시오. 장애가 지속될 경우 시스템 자원 고갈을 막는 서킷 브레이커(Circuit Breaker) 패턴 도입을 강제하십시오.
- **[MUST] Flapping Debounce & Rate Limiting:** 인프라 메트릭이 임계치를 오르락내리락하며 알람이 폭주하는 Flapping 현상을 방어하기 위해, 특정 시간 창(Time Window) 내의 이벤트를 압축/디바운스(Debounce)하거나 Rate Limit 처리를 하는 전처리 계층 구조를 두십시오.

## 2. 장애 시뮬레이션 및 복원력 검증 (Chaos Engineering)
- **[MUST] Fault Injection Testing:** 정상 동작(Happy Path) 케이스만 테스트하는 코드는 프로덕션 퀄리티가 아닙니다. 의도적으로 네트워크 타임아웃, 권한 오류(403), 비정상적으로 큰 페이로드(Payload)를 주입하는 방어 로직 검증 코드(Fault Injection)를 반드시 포함하십시오.
- **[PREFER] Chaos Engineering (AWS FIS / Gremlin):** 인프라의 실제 복원력을 실증하기 위해, AWS Fault Injection Simulator (FIS)나 Gremlin을 도입하여 데이터베이스 페일오버(Failover), 존(AZ) 장애, CPU 스파이크 상황을 정기적으로 시뮬레이션하는 SRE 문화를 워크플로우 제안에 포함시키십시오.
</aiops_validation_edgecases>

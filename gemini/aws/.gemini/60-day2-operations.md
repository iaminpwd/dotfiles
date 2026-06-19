<aws_day2_operations>
# 컨텍스트 모듈: Cloud Native 및 Day-2 운영 표준

## 1. 선언적 배포 및 파이프라인 (CI/CD)
- **[MUST] Separation of Concerns:** CI(빌드/테스트)와 CD(배포) 역할을 엄격히 분리하고, 배포 시 수동 개입을 금지하십시오.
- **[MUST] Explicit Version Pinning (명시적 버전 고정 강제):**
  > You MUST strictly enforce explicit version pinning for container images, Helm charts, and Terraform modules to ensure deterministic deployments, instead of using `latest` tags.

## 2. 가시성 (Observability) 및 데이터 복원력
- **[MUST] Observability:** 인프라 설계 시 기본 모니터링(CloudWatch)을 넘어, 마이크로서비스 환경에 필수적인 분산 추적(OpenTelemetry, AWS X-Ray) 아키텍처를 반드시 포함하십시오.
- **[MUST] Data Resilience:** 데이터베이스 제안 시 고가용성(Multi-AZ)뿐만 아니라 악의적 삭제나 휴먼 에러에 대비한 연속 백업 및 PITR(Point-in-Time Recovery) 활성화를 기본값으로 설정하십시오.

## 3. 재해 복구(DR) 및 롤백 전략
- **[MUST] DR Model:** 멀티 리전 아키텍처 제안 시 RTO/RPO를 고려한 Pilot Light 또는 Warm Standby 모델을 포함하십시오.
- **[MUST] Rollback:** 배포 실패 시 안전한 트래픽 전환(Blue/Green, Canary)과 자동 롤백 파이프라인을 아키텍처에 포함하십시오.
- **[PREFER] Chaos Engineering:** 대규모 엔터프라이즈 환경에서는 서비스 복원력 검증을 위해 AWS FIS (Fault Injection Simulator)를 활용한 카오스 엔지니어링 도입을 고려사항으로 제안하십시오.

## 4. 상태 저장소(DB) 무중단 마이그레이션
- **[Trigger: DB Schema Modification Request] 무중단 DB 마이그레이션 (Zero-Downtime DB):**
  > When a database schema modification is requested, you MUST prioritize proposing a zero-downtime schema migration strategy in a dedicated `db-migration-plan.md` artifact rather than proposing a simple query that causes server downtime.
- **[MUST] Expand and Contract:** 이전 버전 앱과 호환성을 유지하는 하위 호환성 스키마 마이그레이션(Expand and Contract 패턴)과 Flyway, Liquibase 같은 마이그레이션 버전 관리 도구 도입을 반드시 제안하십시오.
</aws_day2_operations>

---
trigger: Apply these rules ONLY when designing CI/CD pipelines, SRE monitoring, observability, disaster recovery (DR), or production deployments.
references:
  - contexts/aws/references/050-iac-standard.md
  - contexts/aws/references/080-database-standard.md
  - contexts/aws/references/030-finops-optimization.md
---
# 컨텍스트 모듈: Cloud Native 및 Day-2 운영 표준

CI/CD 파이프라인 설계 및 Day-2 운영(DR, 가시성) 표준임.

## 1. 핵심 설계 원칙
- **[MUST] Separation of Concerns:** CI와 CD 역할을 분리하고 100% 자동화 배포를 구현할 것.
- **[MUST] Observability:** 인프라 설계 시 기본 모니터링(CloudWatch) 외에 마이크로서비스에 필수적인 분산 추적(OpenTelemetry, AWS X-Ray)을 포함할 것.
- **[MUST] Rollback:** 배포 실패 시 안전한 트래픽 전환(Blue/Green, Canary)과 자동 롤백 메커니즘을 배포 파이프라인 아키텍처에 보증할 것.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 가시성 및 모니터링 알람
- **[MUST] SRE Golden Signals:** 사용자 경험 메트릭(P99 Latency, 5xx Error Rate 등) 위주로 알람을 설계하여 알람의 실질적인 유효성을 높이십시오.
- **[PREFER] Actionable Alerts:** 모든 알람 발생 시 수동 해결 런북(Runbook) 링크를 제공하거나 SNS/Lambda를 연동한 자동화된 조치(Automated Remediation)를 연동할 것.
- **[PREFER] AWS-Side Outage Awareness:** 자사 애플리케이션 장애와 AWS 자체 장애(가용 영역/리전 이슈)를 구분하기 위해 AWS Health Dashboard(Personal Health Dashboard)의 이벤트 알림을 모니터링 파이프라인에 연동할 것.

### 2.2 재해 복구(DR) 및 무중단 마이그레이션
- **[MUST] DR Model:** 멀티 리전 아키텍처 설계 시 비즈니스 RTO/RPO 사양에 따라 Backup & Restore(최저 비용, RTO 수 시간~일), Pilot Light, Warm Standby, Multi-Site Active/Active(최고 비용, RTO 초~분 단위) 4단계 중 요구사항에 부합하는 모델을 명시적으로 선택하여 적용할 것.
- **[MUST] Centralized Backup:** 개별 서비스별 스냅샷 관리에 의존하는 대신, AWS Backup을 통해 계정/리전 간 백업 계획(Backup Plan)과 교차 계정·교차 리전 복제를 중앙 집중형으로 구성할 것.
- **[MUST] Expand and Contract:** DB 스키마 수정 요청 시 하위 호환성을 보장하는 Expand and Contract 패턴을 적용하여 무중단 마이그레이션을 구현할 것.
- **[PREFER] Migration Tool:** Flyway, Liquibase 등 데이터베이스 규격에 맞는 스키마 버전 관리 도구를 채택하여 마이그레이션 이력을 코드로 관리할 것.

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** CI/CD 파이프라인 구문 검증이 에러 없이 패스되고, 스키마 변경 시 `db-migration-plan.md`가 유효하게 작성되어야 합니다.

## 4. 변경 전 확인과 실행 경계
- **[MUST] 중단 조건 (Halt Conditions):**
  - CI/CD 워크플로우 내에 외부 시크릿(Access Key 등)이 평문으로 직접 주입되어 배포 준비가 된 패턴이 스캔 감지되면 즉시 작업을 중단(Hard Block)하고 유출 상태를 보고할 것.
  - 무중단 DB 스키마 마이그레이션이 요구되는 배포 시, 하위 호환성 검증(Expand and Contract) 절차나 롤백 경로가 누락된 경우 작업을 즉시 멈추고 수정을 요구할 것.

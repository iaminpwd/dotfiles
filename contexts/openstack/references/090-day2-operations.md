---
role: Senior OpenStack Architect
priority: high
trigger: Apply these rules ONLY when designing CI/CD pipelines, control-plane lifecycle, observability, disaster recovery (DR), or production deployments.
references:
  - contexts/openstack/references/050-iac-standard.md
  - contexts/openstack/references/080-database-standard.md
  - contexts/openstack/references/030-finops-optimization.md
---
# 컨텍스트 모듈: 컨트롤플레인 수명주기 및 Day-2 운영 표준

본 모듈은 CI/CD 배포 파이프라인, OpenStack 컨트롤플레인 수명주기(배포·업그레이드), SRE 관측성 및 재해 복구(DR) 아키텍처 수립 시 적용되는 기술 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Separation of Concerns:** CI(빌드/테스트)와 CD(배포) 역할을 엄격히 분리하고, 배포 파이프라인에 의한 100% 자동화 배포를 구현하십시오.
- **[MUST] Observability:** 인프라 설계 시 컨트롤플레인 메트릭(openstack-exporter/Gnocchi) 외에 마이크로서비스 분산 추적을 포함하십시오. 관측성 일반 원칙(SLI/SLO, OpenTelemetry 계측 등)은 별도 `observability` 스킬로 위임하여 참조하십시오.
- **[MUST] Rollback:** 배포 실패 시 안전한 트래픽 전환(Blue/Green, Canary)과 자동 롤백 메커니즘을 배포 파이프라인 아키텍처에 보증하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 컨트롤플레인 수명주기 (OpenStack 고유)
- **[MUST] Deployment as Code:** 컨트롤플레인은 수동 구성하지 말고 Kolla-Ansible, OpenStack-Ansible 등 배포 도구의 인벤토리/설정을 코드로 관리하고 Git으로 버전 관리하십시오.
- **[MUST] Rolling Upgrade:** 서비스 업그레이드는 무중단을 위해 컨트롤러 노드를 순차(rolling) 업그레이드하고, 지원 주기가 긴 SLURP 릴리스를 건너뛰기 업그레이드 경로로 우선 검토하십시오. 업그레이드 전 DB(Galera) 백업과 설정 스냅샷을 필수 확보하십시오.
- **[MUST] Ceph Backend Health:** Cinder/Glance/Nova 백엔드로 Ceph 사용 시 `ceph health`(HEALTH_OK)와 OSD near-full 임계치를 배포/업그레이드 전후로 검증하여 스토리지 포화로 인한 컨트롤플레인 장애를 예방하십시오.
- **[MUST] Service HA:** API 서비스는 다중 컨트롤러 + HAProxy/keepalived로 이중화하고, RabbitMQ/Galera 클러스터의 쿼럼 상태를 상시 모니터링하십시오.

### 2.2 관측성·재해 복구(DR)
- **[PREFER] Actionable Alerts:** 모든 알람 발생 시 수동 해결 런북(Runbook) 링크를 제공하거나 자동화된 조치(Automated Remediation)를 연동하십시오.
- **[MUST] DR Model:** 멀티 리전/멀티 사이트 설계 시 RTO/RPO 사양에 따라 Backup & Restore, Warm Standby, Multi-Site Active/Active 중 요구사항에 부합하는 모델을 명시적으로 선택하여 적용하십시오.
- **[MUST] Centralized Backup:** 개별 서비스 스냅샷에 의존하지 말고, 볼륨/이미지/DB 백업을 Swift·Ceph에 중앙 집중형 백업 계획으로 구성하고 교차 사이트 복제를 적용하십시오.
- **[MUST] Expand and Contract:** DB 스키마 수정 시 하위 호환성을 보장하는 Expand and Contract 패턴을 적용하여 무중단 마이그레이션을 구현하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- "CPU 단일 알람 대신, API 5xx 응답 비율이 1%를 초과할 때 슬랙 알람과 런북 가이드를 자동 발송하십시오."
- "업그레이드 전 `ceph health`가 HEALTH_OK인지, Galera 클러스터가 Primary/Synced인지 확인 후 rolling 진행하십시오."
</example>
<example>
[Bad]
- "CPU 70% 초과 시 무조건 호출(PagerDuty) 알람을 전송합니다." (알람 피로 유발)
- "컨트롤러 3대를 동시에 업그레이드하겠습니다." (쿼럼 상실로 컨트롤플레인 다운)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** CI/CD 파이프라인 구문 검증이 에러 없이 패스되고, 컨트롤플레인 변경 시 사전 백업 증적과 `db-migration-plan.md`가 유효하게 작성되어야 합니다.
- **[MUST] 검증 도구 매핑:** 코드 검증은 `contexts/pre-flight-check/SKILL.md`가 지정한 단일 래퍼 명령으로 일괄 수행하십시오.
## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Monitoring/Upgrade Configured] 점검 기준 (절차는 010-openstack-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (알람 피로 방지): 정상적인 스파이크성 트래픽으로 인한 오탐(False Alarm) 피로가 배제되었는가?
  - 기준 2 (안전한 업그레이드): 컨트롤플레인 업그레이드 전 DB 백업·쿼럼 확인·Ceph 헬스 검증 절차가 결합되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - CI/CD 워크플로우 내에 OpenStack 자격 증명(패스워드/Application Credential secret)이 평문으로 직접 주입되어 배포 준비가 된 패턴이 스캔 감지되면 즉시 작업을 중단(Hard Block)하고 유출 상태를 보고하십시오.
  - Ceph가 HEALTH_ERR이거나 Galera 쿼럼이 상실된 상태에서 컨트롤플레인 업그레이드가 시도되면 작업을 즉시 멈추고(Halt & Clarify) 복구를 우선 조치하십시오.

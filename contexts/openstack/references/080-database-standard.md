---
role: Senior OpenStack Architect
priority: high
trigger: Apply these rules ONLY when working with Trove DBaaS or self-managed databases (MySQL, PostgreSQL, Redis) on OpenStack.
references:
  - contexts/openstack/references/050-iac-standard.md
  - contexts/openstack/references/020-security-compliance.md
  - contexts/openstack/references/025-cloud-security.md
  - contexts/openstack/references/030-finops-optimization.md
reviewed: 2026-07-23
---
# 컨텍스트 모듈: 데이터베이스 (Trove / 자체 관리 DB) 엔지니어링 표준

본 모듈은 OpenStack Trove DBaaS 및 Nova+Cinder 기반 자체 관리 데이터베이스(MySQL, PostgreSQL, Redis 등) 설계와 구현 시 적용되는 기술 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] High Availability:** 프로덕션 DB는 Trove replication(또는 자체 관리 시 primary-standby)을 구성하고, 인스턴스를 서로 다른 Availability Zone/Host Aggregate에 분산 배치하여 고가용성을 확보하십시오.
- **[MUST] Data Security:** 데이터 저장 암호화를 위해 Cinder 암호화 볼륨(LUKS, Barbican 키)에 DB 데이터를 배치하고, 스냅샷/백업도 암호화 상태를 유지하십시오.
- **[MUST] Redis Security:** Redis 생성 시 반드시 `requirepass`(AUTH)와 전송 중 데이터 암호화(TLS)를 동시에 활성화하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 Trove 및 관계형 데이터베이스
- **[MUST] Automated Backups:** Trove 자동 백업(Swift 저장)을 활성화하고 보존 기간을 최소 7일 이상으로 구성하십시오. 자체 관리 DB는 `cron` 기반 논리 백업을 Swift로 업로드하도록 설계하십시오.
- **[MUST] Datastore Version Pinning:** Trove datastore 버전(`--datastore-version`)을 명시적으로 고정하고, 벤더 지원이 유효한 안정 버전을 선택하십시오.
- **[MUST] Connection Management:** 접속자가 몰리는 고성능 웹 서비스 DB 전면에는 커넥션 풀링(ProxySQL/PgBouncer)을 배치하여 커넥션 폭주를 흡수하십시오.
- **[PREFER] Read Scaling:** 읽기 트래픽 비중이 높은 워크로드는 read replica를 구성하여 쓰기 인스턴스의 부하를 분산하십시오.

### 2.2 캐시 및 데이터 수명 주기
- **[MUST] Cache Sizing:** Redis 등 인메모리 캐시는 `maxmemory`와 eviction 정책을 명시하여 OOM으로 인한 DB 캐시 노드 다운을 방지하십시오.
- **[MUST] Backup Restore Drill:** 백업만 설정하고 방치하지 말고, 백업으로부터 인스턴스 복원(`openstack database instance create --backup <backup_id>`) 또는 자체 관리 DB의 논리 복원을 주기적으로 리허설하여 RPO/RTO를 실증하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- "커넥션 병목을 줄이기 위해 PgBouncer를 연동하여 커넥션을 재사용하십시오."
- "자주 조회되는 컬럼에 인덱스를 걸고 실행 계획(Explain) 상의 Full Table Scan 여부를 검증하십시오."
</example>
<example>
[Bad]
- "애플리케이션에서 DB로 풀링 없이 수만 개의 커넥션을 직접 오픈하도록 둡니다."
- "속도가 느리므로 인스턴스 Flavor를 즉시 4배로 스케일업합니다."
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** DB IaC 파일 내에 볼륨 암호화 옵션과 백업 정책이 누락 없이 선언되고, 보안 그룹 규칙 상 DB 포트가 전면 개방되지 않았음이 린팅 도구를 통해 검증되어야 합니다.
- **[MUST] 검증 도구 매핑:** `tflint` 또는 `checkov`로 DB 관련 IaC 파일의 암호화 미설정 및 백업 정책 누락을 자동 스캔하고, DB 인바운드 보안 그룹 소스가 특정 Web/WAS 보안 그룹으로만 제한되어 있는지 확인하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Schema Modified] 점검 기준 (절차는 010-openstack-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (락 리스크 최소화): DDL 쿼리가 프로덕션 테이블 전체에 Table Lock을 유발하여 API 장애를 일으킬 가능성이 없는가?
  - 기준 2 (보안 노출): DB 인스턴스에 floating IP가 직접 연결되어 외부에 노출될 우려가 없는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - DB 인스턴스에 floating IP가 직접 연결되거나 보안 그룹 상 DB 포트(3306, 5432 등)가 `0.0.0.0/0`에 노출되는 위험이 발견될 시 즉시 작업을 중단(Hard Block)하고 보안 경고를 발송하십시오.
  - Cinder 암호화 볼륨 없이 평문 볼륨에 프로덕션 DB 데이터를 배치하는 설계가 시도될 경우 작업을 즉시 멈추고 보안 수정을 강제하십시오.

---
role: Senior Cloud Architect
priority: high
trigger: Apply these rules ONLY when working with Azure Database for PostgreSQL/MySQL, Azure SQL Database, Cosmos DB, Azure Cache for Redis, or database engineering.
references:
  - contexts/azure/references/050-iac-standard.md
  - contexts/azure/references/020-security-compliance.md
  - contexts/azure/references/025-cloud-security.md
  - contexts/azure/references/030-finops-optimization.md
---
# 컨텍스트 모듈: 데이터베이스 (Azure Database for PostgreSQL/MySQL, Cosmos DB, Azure Cache for Redis) 엔지니어링 표준

본 모듈은 Azure SQL Database, Open Source DB, NoSQL Cosmos DB 및 인메모리 캐시 Azure Cache for Redis 설계와 구현 시 적용되는 기술 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] High Availability:** 프로덕션 DB 클러스터에는 반드시 가용 영역 중복(Zone-Redundant) 배포 아키텍처를 적용하여 고가용성을 확보하십시오.
- **[MUST] Data Security:** 데이터베이스 스토리지 암호화(Encryption at Rest)를 활성화하고, 암호화 키는 Azure Key Vault 고객 관리형 키(CMK)를 지정하십시오.
- **[MUST] Redis Security:** Redis 클러스터 생성 시 반드시 `AUTH` 토큰 인증과 전송 중 데이터 암호화(TLS)를 동시에 활성화하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 관계형 데이터베이스 (Azure Database for PostgreSQL/MySQL & Azure SQL Database)
- **[MUST] Automated Backups:** 자동 백업을 활성화하고 보존 기간(Retention Period)을 최소 7일 이상으로 구성하십시오.
- **[PREFER] Serverless Tier:** 개발/테스트 환경 또는 트래픽 변동폭이 극심한 쿼리 워크로드는 Azure SQL Database Serverless 아키텍처 사용을 우선 검토하십시오.
- **[MUST] Connection Management:** 접속자가 몰리는 고성능 PostgreSQL 전면에는 커넥션 풀링 관리를 위해 PgBouncer 배포를 설계하십시오.

### 2.2 NoSQL 및 캐시 데이터베이스
- **[MUST] Capacity Mode Selection:** Cosmos DB 설계 시 트래픽 예측이 어려운 신규 서비스는 **Serverless** 모드를 사용하고, 안정적인 워크로드는 **Provisioned Throughput(Autoscale)**을 적용하십시오.
- **[MUST] Data Lifecycle (TTL):** 세션 정보 등 임시 데이터 수집 테이블에는 비용 통제를 위해 Cosmos DB TTL(Time To Live) 속성을 필수로 기재하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- "커넥션 병목을 줄이기 위해 PgBouncer를 연동하여 자원을 최적화하십시오."
- "자주 조회되는 컬럼에 인덱스를 걸고 실행 계획(Explain) 상의 Full Table Scan 여부를 검증하십시오."
</example>
<example>
[Bad]
- "애플리케이션에서 DB로 PgBouncer 없이 수만 개의 커넥션을 직접 오픈하도록 둡니다."
- "속도가 느리므로 인프라 인스턴스 스펙을 즉시 4배로 스케일업합니다."
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** DB IaC 파일 내에 암호화 옵션과 백업 정책이 누락 없이 선언되고, NSG 규칙 상 DB 포트가 전면 개방되지 않았음이 린팅 도구를 통해 검증되어야 합니다.
- **[MUST] 검증 도구 매핑:** `tflint` 또는 `checkov`를 활용해 DB 관련 IaC 파일의 암호화 미설정 및 백업 정책 누락을 자동 스캔하십시오. DB 인바운드 보안 그룹 규칙 소스가 특정 Web/WAS 서브넷 및 애플리케이션 보안 그룹(ASG)으로만 제한되어 있는지 확인하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Schema Modified] 도메인 자가 채점:** 데이터베이스 스키마(DDL), 인덱스 쿼리 및 디스크 프로비저닝 코드를 제안/수정한 직후, 스스로 `<self_critique>` 태그를 열어 아래 2가지 점검 기준으로 1~5점 채점을 수행하고 사유를 명시하십시오. (두 기준 모두 5점 만점일 때만 작업을 승인 요청하십시오)
  - 기준 1 (락 리스크 최소화): DDL 쿼리가 프로덕션 테이블 전체에 Table Lock을 유발하여 API 장애를 일으킬 가능성이 없는가?
  - 기준 2 (보안 노출): DB의 Public Network Access 속성이 활성화되어 외부 공격에 노출될 우려가 없는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - DB 리소스의 Public Access (`public_network_access_enabled = true`) 설정이 감지되거나 NSG 상 DB 포트가 `0.0.0.0/0`에 노출되는 위험이 발견될 시 즉시 작업을 중단(Hard Block)하고 보안 경고를 발송하십시오.
  - Key Vault CMK 암호화 옵션(예: `customer_managed_key` 누락)이 비활성화된 상태로 SQL DB 생성이 시도될 경우 작업을 즉시 멈추고 보안 수정을 강제하십시오.

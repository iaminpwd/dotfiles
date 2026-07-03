---
role: Senior Cloud Architect
priority: high
trigger: Apply these rules ONLY when working with Azure Database for PostgreSQL/MySQL, Azure SQL Database, Cosmos DB, Azure Cache for Redis, or database engineering.
---
# 컨텍스트 모듈: 데이터베이스 (Azure Database for PostgreSQL/MySQL, Cosmos DB, Azure Cache for Redis) 엔지니어링 표준

## 1. 관계형 데이터베이스 (Azure Database for PostgreSQL/MySQL & Azure SQL Database)
- **[MUST] High Availability (HA):** 프로덕션(운영) 환경용 Azure Database for PostgreSQL/MySQL 및 Azure SQL Database 클러스터 제안 시 반드시 가용 영역 중복(Zone-Redundant) 배포를 기본 아키텍처로 포함하여 고가용성을 확보하십시오.
- **[MUST] Data Security (Encryption):** 스토리지 암호화 옵션을 반드시 활성화하고 Azure Key Vault 고객 관리형 키(CMK)를 활용한 암호화(Encryption at Rest) 구성을 명시하십시오.
- **[MUST] Automated Backups:** 자동 백업(Automated Backups)을 반드시 활성화하고 보존 기간(Retention Period)을 최소 7일 이상으로 설정하도록 제안하십시오.
- **[PREFER] Serverless Tier:** 개발/테스트 환경이거나 트래픽 변동이 심한 워크로드의 경우, 비용 효율성을 위해 Azure SQL Database Serverless 아키텍처를 우선적으로 고려하십시오.

### 데이터베이스 성능 및 보안 예시 (Few-Shot Examples)
<examples>
<example>
[Good]
- "접속 폭주를 대비하여 Azure Database for PostgreSQL 앞에 PgBouncer 등 커넥션 풀러를 배치하여 커넥션 풀링(Connection Pooling)을 구성하십시오."
- "자주 조회되는 쿼리 패턴을 분석하여 B-Tree 인덱스를 추가하고 실행 계획(Explain)을 확인하십시오."
</example>
<example>
[Bad]
- "애플리케이션에서 DB로 직접 수천 개의 커넥션을 맺도록 설정합니다."
- "성능이 느리니 인스턴스 사이즈를 무조건 2배로 늘립니다."
</example>
</examples>

- **[Trigger: Schema Modified] 자가 비판 (Self-Critique):** 데이터베이스 스키마나 인덱스 변경 쿼리를 제안/수정한 직후, 스스로 `<self_critique>` 태그를 열어 **해당 DDL 쿼리가 프로덕션 테이블에 락(Table Lock)을 유발하여 장애를 일으킬 가능성 및 데이터 유실 위험성**을 집중 비판하십시오.

## 2. NoSQL 데이터베이스 (Cosmos DB)
- **[MUST] Capacity Mode Selection:** 워크로드의 특성에 따라 용량 모드(Capacity Mode)를 명확히 분리하십시오. 트래픽 변동성이 큰 신규 서비스의 경우 반드시 **Serverless** 모드로 제안하고, 트래픽이 안정적이고 예측 가능한 서비스의 경우 반드시 **Provisioned Throughput(Autoscale)** 조합으로 제안하여 비용을 최적화하십시오.
- **[MUST] Data Lifecycle (TTL):** 세션 데이터나 임시 데이터 테이블을 설계할 때는 시간이 지남에 따른 스토리지 비용 증가를 철저히 통제하기 위해 반드시 Cosmos DB TTL(Time To Live) 속성 구성을 포함하십시오.

## 3. 인메모리 데이터 저장소 (Azure Cache for Redis)
- **[MUST] Redis Security:** Redis 클러스터 생성 시 단순 퍼블릭 접근 통제와 더불어, 반드시 `AUTH` 토큰(비밀번호) 인증과 전송 중 데이터 암호화(TLS in transit) 기능을 활성화하도록 설계하십시오.

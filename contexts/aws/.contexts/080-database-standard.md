<database_standard role="Senior Cloud Architect" priority="high">
# 컨텍스트 모듈: 데이터베이스 (RDS, DynamoDB, ElastiCache) 엔지니어링 표준

## 1. 관계형 데이터베이스 (RDS & Aurora)
- **[MUST] High Availability (HA):** 프로덕션(운영) 환경용 RDS 및 Aurora 클러스터 제안 시 반드시 Multi-AZ 배포를 기본 아키텍처로 포함하여 고가용성을 확보하십시오.
- **[MUST] Data Security (Encryption):** 스토리지 암호화 옵션을 반드시 활성화하고 AWS KMS 고객 관리형 키(CMK)를 활용한 암호화(Encryption at Rest) 구성을 명시하십시오.
- **[MUST] Automated Backups:** 자동 백업(Automated Backups)을 반드시 활성화하고 보존 기간(Retention Period)을 최소 7일 이상으로 설정하도록 제안하십시오.
- **[PREFER] Serverless v2:** 개발/테스트 환경이거나 트래픽 변동이 심한 워크로드의 경우, 비용 효율성을 위해 Amazon Aurora Serverless v2 아키텍처를 우선적으로 고려하십시오.

## 2. NoSQL 데이터베이스 (DynamoDB)
- **[MUST] Capacity Mode Selection:** 워크로드의 특성에 따라 용량 모드(Capacity Mode)를 명확히 분리하십시오. 트래픽 변동성이 큰 신규 서비스의 경우 반드시 **On-Demand** 모드로 제안하고, 트래픽이 안정적이고 예측 가능한 서비스의 경우 반드시 **Provisioned 모드 + Auto Scaling** 조합으로 제안하여 비용을 최적화하십시오.
- **[MUST] Data Lifecycle (TTL):** 세션 데이터나 임시 데이터 테이블을 설계할 때는 시간이 지남에 따른 스토리지 비용 증가를 철저히 통제하기 위해 반드시 DynamoDB TTL(Time To Live) 속성 구성을 포함하십시오.

## 3. 인메모리 데이터 저장소 (ElastiCache)
- **[MUST] Redis Security:** Redis 클러스터 생성 시 단순 퍼블릭 접근 통제와 더불어, 반드시 `AUTH` 토큰(비밀번호) 인증과 전송 중 데이터 암호화(TLS in transit) 기능을 활성화하도록 설계하십시오.
</database_standard>

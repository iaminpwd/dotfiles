---
trigger: Apply these rules ONLY when working with RDS, Aurora, DynamoDB, ElastiCache, or database engineering.
references:
  - contexts/aws/references/050-iac-standard.md
  - contexts/aws/references/020-security-compliance.md
  - contexts/aws/references/025-cloud-security.md
  - contexts/aws/references/030-finops-optimization.md
---
# 컨텍스트 모듈: 데이터베이스 (RDS, DynamoDB, ElastiCache) 엔지니어링 표준

관계형/NoSQL/인메모리 데이터베이스 설계 표준임.

## 1. 핵심 설계 원칙
- **[MUST] High Availability:** 프로덕션 DB에는 Multi-AZ 배포를 적용할 것.
- **[MUST] Data Security:** 데이터베이스 스토리지 암호화(Encryption at Rest)를 활성화하고, 암호화 키는 AWS KMS 고객 관리형 키(CMK)를 지정할 것.
- **[MUST] Redis Security:** Redis 클러스터 생성 시 반드시 `AUTH` 토큰 인증과 전송 중 데이터 암호화(TLS)를 동시에 활성화할 것.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 관계형 데이터베이스 (RDS & Aurora)
- **[MUST] Automated Backups:** 자동 백업을 활성화하고 보존 기간(Retention Period)을 최소 7일 이상으로 구성할 것.
- **[PREFER] Serverless v2:** 개발/테스트 환경 또는 트래픽 변동폭이 극심한 쿼리 워크로드는 Aurora Serverless v2 아키텍처 사용을 우선 검토할 것.
- **[PREFER] Connection Management:** 접속자가 몰리는 고성능 웹 서비스 RDS 전면에는 커넥션 풀링 관리를 위해 RDS Proxy 배포를 설계할 것.
- **[PREFER] Read Scaling:** 읽기 트래픽 비중이 높은 워크로드는 Read Replica를 구성하여 쓰기 인스턴스의 부하를 분산할 것.
- **[MUST] Safe Major Version Upgrade:** 프로덕션 RDS/Aurora의 메이저 버전 업그레이드 시, 다운타임 없이 문제 발생 시 즉시 롤백 가능한 Blue/Green Deployments를 우선 적용할 것.

### 2.2 NoSQL 및 캐시 데이터베이스
- **[MUST] Capacity Mode Selection:** DynamoDB 설계 시 트래픽 예측이 어려운 신규 서비스는 **On-Demand** 모드를 사용하고, 안정적인 워크로드는 **Provisioned 모드 + Auto Scaling**을 적용할 것.
- **[MUST] Data Lifecycle (TTL):** 세션 정보 등 임시 데이터 수집 테이블에는 비용 통제를 위해 DynamoDB TTL(Time To Live) 속성을 필수로 기재할 것.

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** DB IaC 파일 내에 암호화 옵션과 백업 정책이 누락 없이 선언되고, 보안 그룹 규칙 상 DB 포트가 전면 개방되지 않았음이 린팅 도구를 통해 검증되어야 합니다.

## 4. 변경 전 확인과 실행 경계
- **[MUST] DDL 실행 전 확인:** 운영 DB의 스키마를 변경하기 전에 Table Lock 발생 가능성과 서비스 영향을 확인할 것.
- **[MUST] 중단 조건 (Halt Conditions):**
  - DB 리소스의 Public Access (`publicly_accessible = true`) 설정이 감지되거나 보안 그룹 상 DB 포트(3306, 5432 등)가 `0.0.0.0/0`에 노출되는 위험이 발견될 시 즉시 작업을 중단(Hard Block)하고 보안 경고를 발송할 것.
  - KMS CMK 암호화 옵션(`storage_encrypted = false`)이 비활성화된 상태로 RDS 생성이 시도될 경우 작업을 즉시 멈추고 보안 수정을 강제할 것.

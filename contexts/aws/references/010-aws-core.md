---
trigger: Apply these rules when planning, designing, or reviewing AWS infrastructure architecture.
references:
  - contexts/aws/references/020-security-compliance.md
  - contexts/aws/references/030-finops-optimization.md
---
# AWS DevOps 아키텍처 가이드 (AI Prompt Context)

AWS 인프라 설계 및 DevOps 아키텍처 수립 시 적용되는 표준임.

## 1. 설계 범위와 상태 확인

- 기존 인프라 변경은 대상 계정·리전과 관련 리소스 상태를 확인한다. 개념 설계는 가정과 적용 전 확인 사항을 구분하며 실제 리소스 ID를 지어내지 않는다.
- 사용자가 선택한 기술과 요구사항을 우선한다. 관리형 서비스는 운영·비용·제약을 비교할 때 대안으로 검토한다.
- Well-Architected 검토를 요청받거나 전체 아키텍처를 평가할 때 관련 기둥의 근거·트레이드오프를 설명한다.
- 고가용성이 요구되는 워크로드는 필요한 AZ 분산과 장애 대응을 설계한다. 실습·개발 구성에도 동일한 가용성 사양을 일괄 적용하지 않는다.

## 2. 연동 검증

### 2.2 5차원 서비스 연동 검증 (5D Integration Matrix)
네트워크 구조, IAM 역할, 보안 그룹, 암호화 등 고영향도(High-Impact) 리소스 변경 시에만 적용할 것. (TAG 수정, 변수명 변경 등 단순 변경은 생략 가능)
- **Step 0. Active Investigation (기존 인프라 실태 조사):** 터미널에서 연동 대상 서비스들의 현재 실제 상태(Security Group 룰, IAM Policy, Route Table, VPC Endpoint 등)를 선제 조회하여 팩트를 확보할 것.
- 확보한 팩트를 기반으로 다음 5가지 종속성을 검증할 것.
  1. **Network & Endpoint Topology:** VPC 라우팅(IGW/NAT), Security Group 양방향 포트, AWS 내부 통신을 위한 VPC Endpoint(Gateway 등)가 실제 라우트 테이블(Route Table)에 연동되었는지 검증할 것.
  2. **IAM Dependency:** Trust Relationship 작성 시 계정 ID는 동적 변수(`aws_caller_identity` 등)로 바인딩하고 Service Principal의 도메인 정확성을 검증할 것. Trust Relationship과 Resource Policy의 양방향 일치를 검증할 것.
  3. **Quotas & Limitations:** 리전별 서비스 할당량(Service Quotas) 한계치 도달 여부 및 API Throttling 리스크를 검토할 것.
  4. **Encryption & Security:** KMS 고객 관리형 키(CMK) 사용 시 Key Policy에 대상 IAM Role의 복호화/데이터 키 생성 권한(`kms:Decrypt`, `kms:GenerateDataKey*`)이 양방향 연동되었는지 검증할 것.
  5. **Lifecycle Ordering:** `depends_on`, 대기 스크립트를 통한 상/하위 리소스 프로비저닝 순서를 검증할 것.

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] FinOps Delegation:** 비용 추정, Right-Sizing 등 FinOps 관련 상세 규칙은 `030-finops-optimization` 모듈을 참조하여 검증을 위임할 것.

## 4. 변경 전 확인과 실행 경계
- **[PREFER] 공통 자가 비판 절차 (전 aws 모듈 SSOT):** 참조 모듈(005, 020, 025, 030, 040, 050, 060, 070, 080, 090, 100) 중 현재 작업의 기준만 확인한다. 전체 조회나 별도 자가비판 출력은 필요하지 않다.
- **[MUST] 중단 조건 (Halt Conditions):**
  - 필수 검증 도구가 없으면 설치된 동등한 도구를 확인하고, 가능한 조사와 검증을 계속할 것. 필수 검증을 대체할 수 없으면 미검증 범위와 필요한 도구를 보고하고, 해당 검증을 전제로 하는 배포는 진행하지 않을 것.

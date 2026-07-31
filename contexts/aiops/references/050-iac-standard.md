---
role: Senior AIOps Engineer
priority: high
trigger: Apply these rules ONLY when designing GitOps, IaC pipelines, or AI Model Serving infrastructure.
references:
  - contexts/aiops/references/010-aiops-core.md
  - contexts/aiops/references/020-security-compliance.md
  - contexts/aiops/references/030-finops-optimization.md
---
# 컨텍스트 모듈: Enterprise AIOps IaC 및 GitOps 아키텍처 표준

인프라 프로비저닝, 자동화 파이프라인 및 GitOps 배포 아키텍처 수립 시 적용되는 표준입니다.

## 1. 핵심 설계 원칙
- **[MUST] State Locking & Isolation:** IaC 작성 시 원격 백엔드/Lock을 구성하고 환경(개발/운영) 상태를 물리 격리하십시오. (이유: 상태 충돌 차단)
- **[PREFER] Stateless Over Stateful:** 연산 컨테이너는 무상태 아키텍처로 설계하고 상태 관리는 관리형 서비스에 위임하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 배포 아키텍처 및 복원력
- **[PREFER] Immutable Infrastructure:** 리소스 구성 변경 시 기존 리소스를 덮어쓰거나 직접 수정(Mutable)하는 대신, 새로운 리소스를 프로비저닝하고 트래픽을 넘긴 뒤 이전 리소스를 폐기하는 불변 인프라(Immutable) 패턴을 적용하십시오.
- **[MUST] Asynchronous Event-Driven & DLQ:** 비동기 구간에는 DLQ 연동 백업 아키텍처를 구성하십시오. (이유: 이벤트 유실 방지)

### 2.2 엔터프라이즈 명명 규칙 및 보안
- **[MUST] Resource Naming Standard:** 리소스에 표준 명명 규칙(`<Project>-<Env>...`)을 적용하십시오. (이유: 리소스 식별 용이성)
- **[MUST] Zero-Trust 엔드포인트 통제:** LLM 모델 엔드포인트는 프라이빗 서브넷에 배치 및 프록시를 통해 접근하십시오. (이유: 무단 통신 차단)

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- Terraform S3 백엔드 락 설정 예시:
```hcl
terraform {
  backend "s3" {
    bucket         = "myproject-tfstate-bucket"
    key            = "prod/aiops/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "myproject-tfstate-lock"
  }
}
```
</example>
<example>
[Bad]
- 로컬 백엔드 사용 (동시 실행 시 State 깨짐 및 충돌 발생 안티패턴)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** `tflint` 및 `shellcheck` 검사가 성공하고, 배포 실행 시 정량적 이력이 `iac-deployment-summary.md`에 문서화되어야 합니다.
- **[MUST] 검증 도구 매핑:** 코드 검증은 `contexts/pre-flight-check/SKILL.md`가 지정한 단일 래퍼 명령으로 일괄 수행하십시오. 단, `checkov` 스캔 결과 수정이 불가능한 항목은 반드시 `#checkov:skip` 주석과 근거를 명시하여 예외 처리하십시오.
## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Before State Mutation] 점검 기준 (절차는 010-aiops-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (영향 반경): 상태 변경 명령이 기존 가동 중인 타 서비스 영역(DB, Network)을 차단/오염시킬 위험도가 없는가?
  - 기준 2 (환경 격리): 개발용 배포 스크립트가 운영(Production) State 영역을 물리적으로 격리하여 상태 침투를 방어하는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 테넌트/모델 서버의 API 포트가 VPN 등 게이트웨이 우회 필터 없이 퍼블릭 `0.0.0.0/0`에 무단 개방된 IaC 매니페스트가 감지될 시 즉시 작업을 중단(Hard Block)하고 프라이빗 VPC 경로로 격리하십시오.
  - Terraform `apply` 또는 `destroy` 등 고위험 명령어를 선언하면서, 파급 효과 분석(Blast Radius Analysis) 및 사전 `[수정 승인]` 단계가 생략되었을 시 작업을 즉시 멈추고 승인 양식을 발송하십시오.

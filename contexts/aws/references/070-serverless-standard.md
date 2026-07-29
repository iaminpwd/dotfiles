---
role: Senior Cloud Architect
priority: high
trigger: Apply these rules ONLY when working with AWS Lambda, API Gateway, Step Functions, or event-driven architecture.
references:
  - contexts/aws/references/050-iac-standard.md
  - contexts/aws/references/020-security-compliance.md
  - contexts/aws/references/025-cloud-security.md
  - contexts/aws/references/030-finops-optimization.md
---
# 컨텍스트 모듈: Serverless 및 Event-driven 아키텍처

서버리스 및 이벤트 구동형 아키텍처 설계 표준임.

## 1. 핵심 설계 원칙
- **[MUST] State Isolation:** Lambda 함수는 무상태로 설계하고 데이터는 외부 저장소(DynamoDB 등)에 분리할 것. (이유: 서버리스 확장성 보장)
- **[MUST] Failure Handling & Retry:** 모든 비동기 Lambda 호출 및 이벤트 트리거(SQS, SNS, Kinesis 등)에는 메시지 처리 신뢰성 확보를 위해 Dead Letter Queue (DLQ) 또는 On-Failure Destinations를 필수 구성할 것.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 이벤트 소스 및 API 게이트웨이 보안
- **[PREFER] Event-driven:** EventBridge, SQS, Kinesis Data Streams 등을 활용한 비동기식 이벤트 기반 흐름을 최우선 제안하고, 복잡한 비즈니스 로직은 Step Functions 오케스트레이션으로 분리할 것.
- **[MUST] API Security:** API Gateway 제안 시 반드시 IAM 인증, Cognito User Pool, 또는 Lambda Custom Authorizer를 필수 구성하여 퍼블릭 무단 접근을 안전하게 격리할 것.
- **[MUST] Performance Optimization:** 레이턴시 민감 API 설계 시, 콜드 스타트 극복을 위해 Provisioned Concurrency 설정 또는 Rust/Go 등 빠른 구동 런타임 사용을 대안으로 검토할 것.
- **[MUST] Throttling Protection:** 다운스트림(DB 등) 자원 과부하나 계정 단위 동시 실행 한도 안정성을 보장하기 위해 트래픽이 큰 Lambda 함수에는 Reserved Concurrency를 설정할 것.

### 2.2 배포 패키징 및 Boto3 개발 표준
- **[PREFER] Container Image:** Lambda 종속성 용량 한계 극복을 위해 Zip 파일보다 컨테이너 이미지 배포 아키텍처를 우선 제안할 것.
- **[MUST] Boto3 Safety:** Python AWS SDK(Boto3) 사용 시, 대량 조회용 `Paginator` 적용 및 `botocore` 예외 처리(`ClientError`)를 반드시 포함할 것.
- **[MUST] API Call Idempotency:** Boto3/CLI를 통한 리소스 생성 스크립트 작성 시, 중복 생성을 막기 위해 반드시 고유 식별자(`ClientRequestToken` 등)를 포함할 것.
- **[PREFER] Observability Tooling:** 구조화된 로깅, 분산 추적, 커스텀 메트릭 계측을 위해 AWS Lambda Powertools(Python/TypeScript/Java) 사용을 우선 제안할 것.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
```hcl
resource "aws_lambda_function_event_invoke_config" "example" {
  function_name                = aws_lambda_function.example.function_name
  maximum_event_age_in_seconds = 60
  maximum_retry_attempts       = 2

  destination_config {
    on_failure {
      destination = aws_sqs_queue.dlq.arn
    }
  }
}
```
</example>
<example>
[Bad]
```hcl
# maximum_retry_attempts 설정 누락 (이벤트 유실 및 무한 루프 위험)
# failure destination 누락 (에러 시 유실된 메시지 추적 불가)
```
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** AWS SAM CLI를 통해 템플릿의 형식이 에러 없이 검증되고, 로컬 시뮬레이션(`sam local invoke` 등)을 거쳐 이진(Pass/Fail) 결과를 획득해야 합니다.
## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Serverless Deployed] 점검 기준 (절차는 010-aws-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (오류 격리): 비동기 이벤트 처리 실패 시 Dead Letter Queue (DLQ)로 자동 격리(On-Failure)되는 경로가 설정되었는가?
  - 기준 2 (보안 통제): API Gateway의 퍼블릭 엔드포인트에 인증(IAM/Cognito 등) 장치가 누락 없이 결합되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - Lambda 함수의 메모리 및 타임아웃 할당량이 비합리적으로 과도하게 높게 설정(예: 타임아웃 15분 및 메모리 10GB 상시 적용)되어 리소스 낭비 위험성이 확인될 시 작업을 즉시 중단(Halt & Clarify)하고 최적화를 요청할 것.
  - SQS/SNS 비동기 파이프라인에서 DLQ 유실이 확인되고 수동 재처리 복구 계획이 부재할 시 작업을 멈추고 대체 설계를 구현할 것.

<domain_specific_rules instruction="Apply these rules only if the current task involves the specific technology.">
<serverless_standard role="Senior Cloud Architect" priority="high">
# 컨텍스트 모듈: Serverless 및 Event-driven 아키텍처

## 1. Serverless 설계 원칙
- **[PREFER] Event-driven:** SQS, SNS, EventBridge, **Kinesis Data Streams** 등을 활용한 비동기식(Asynchronous) 이벤트 기반 아키텍처를 최우선으로 제안하십시오.
- **[MUST] State Isolation:** AWS Lambda 함수 설계 시 반드시 무상태(Stateless)로 설계하고 필요한 데이터는 DynamoDB 등 외부 저장소를 활용하도록 구성하십시오.
- **[MUST] Orchestration:** 복잡한 비즈니스 로직(Workflow) 구현 시 AWS Step Functions를 활용한 오케스트레이션을 적극 제안하십시오.
- **[MUST] Performance Optimization (Cold Start):** 지연 시간(Latency)에 민감한 API 설계 시, 콜드 스타트 이슈를 극복하기 위해 Provisioned Concurrency 설정이나 구동이 빠른 런타임(Rust, Go 등) 전환을 필수 대안으로 제시하십시오.

## 2. 보안 및 오류 처리
- **[MUST] Failure Handling & Retry:** 모든 비동기 Lambda 호출 및 이벤트 트리거(SQS, EventBridge, **Kinesis** 등)에는 메시지 처리의 신뢰성을 보장하기 위해 **Dead Letter Queue (DLQ), On-Failure Destinations 또는 스트림 에러 제어(예: BisectBatchOnFunctionError)**를 구성하고 재시도(Retry) 정책을 명시하십시오.
- **[MUST] API Security:** API Gateway 제안 시 반드시 IAM 인증, Cognito User Pool, 또는 Lambda Custom Authorizer를 필수 구성 요소로 포함하여 퍼블릭 접근을 통제하십시오.

### 비동기 오류 제어 예시 (Few-Shot Examples)
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
# maximum_retry_attempts 설정 누락 (무한 재시도 위험)
# DLQ(on_failure destination) 누락 (메시지 유실)
</example>
</examples>

- **[Trigger: Serverless Deployed] 자가 비판 (Self-Critique):** 서버리스 아키텍처(Lambda, SQS, SNS 등) 구성을 제안/수정한 직후, 스스로 `<self_critique>` 태그를 열어 **비동기 이벤트 처리 실패 시 무한 재시도(Infinite Loop) 발생 가능성 및 Dead Letter Queue (DLQ) 누락으로 인한 메시지 영구 유실 가능성**을 집중 비판하십시오.

## 3. 배포 및 패키징
- **[PREFER] Container Image:** 배포 패키징 시 종속성(Dependencies) 용량 한계를 극복하고 로컬 테스트 용이성을 확보하기 위해, Zip 파일 방식보다 **컨테이너 이미지(Container Image) 배포** 방식을 우선 고려하십시오.
- **[MUST] SAM Local Testing (CLI):** AWS SAM(Serverless Application Model) 기반의 인프라 코드 작성 시 반드시 `run_command`로 `sam validate -t <특정_템플릿_파일>`을 실행하여 템플릿 문법을 사전 검증하십시오. 만약 로컬에 도구가 설치되어 있지 않다면 절대 임의로 건너뛰지 말고 즉시 작업을 중단(Halt & Clarify)한 뒤 사용자에게 설치를 요구하십시오.
- **[MUST] Boto3 Safety:** Python AWS SDK(Boto3) 기반의 Lambda 코드 작성 및 리뷰 시, 대량 조회용 `Paginator` 사용 및 `botocore` 예외 처리(ClientError) 안정성 확보를 깐깐하게 검토하십시오.
- **[Trigger: After Lambda Code Edit] 로컬 인보크 테스트 (Local Invoke Trigger):** 수정된 Lambda 코드를 클라우드에 배포하기 전, 반드시 `run_command`를 통해 `sam local invoke` 또는 `sam local start-api`를 실행하여 로컬에서 함수를 시뮬레이션(테스트)하십시오. 만약 로컬에 도구가 설치되어 있지 않다면 절대 임의로 건너뛰지 말고 즉시 작업을 중단(Halt & Clarify)한 뒤 사용자에게 설치를 요구하십시오.
</serverless_standard>
</domain_specific_rules>

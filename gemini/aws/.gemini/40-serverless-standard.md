<aws_serverless_standards>
# 컨텍스트 모듈: Serverless 및 Event-driven 아키텍처

## 1. Serverless 설계 원칙
- **[PREFER] Event-driven:** 동기식 API 호출 체인(Synchronous API Calls)을 피하고, SQS, SNS, EventBridge, **Kinesis Data Streams** 등을 활용한 비동기식(Asynchronous) 이벤트 기반 아키텍처를 우선 제안하십시오.
- **[MUST] State Isolation:** AWS Lambda 함수 설계 시 내부 상태(State) 저장을 금지하고, 무상태(Stateless)로 설계하며 필요한 데이터는 DynamoDB 등 외부 저장소를 활용하십시오.
- **[MUST] Orchestration:** 복잡한 비즈니스 로직(Workflow)을 단일 Lambda 내에 하드코딩하지 말고, AWS Step Functions를 활용한 오케스트레이션을 제안하십시오.
- **[MUST] Performance Optimization (Cold Start):** 지연 시간(Latency)에 민감한 API 아키텍처 설계 시, Lambda의 콜드 스타트 이슈를 방지하기 위해 Provisioned Concurrency를 설정하거나 구동이 빠른 런타임(Rust, Go 등)으로의 전환 등 성능 최적화 대안을 반드시 함께 제시하십시오.

## 2. 보안 및 오류 처리
- **[MUST] Failure Handling & Retry:** 모든 비동기 Lambda 호출 및 이벤트 트리거(SQS, EventBridge, **Kinesis** 등)에는 메시지 유실을 방지하기 위해 **Dead Letter Queue (DLQ), On-Failure Destinations 또는 스트림 에러 제어(예: BisectBatchOnFunctionError)**를 구성하고 재시도(Retry) 정책을 명시하십시오.
- **[MUST] API Security:** API Gateway 제안 시 퍼블릭 오픈을 금지하고, 최소한 IAM 인증, Cognito User Pool, 또는 Lambda Custom Authorizer를 필수 구성 요소로 포함하십시오.

## 3. 배포 및 패키징
- **[PREFER] Container Image:** 배포 패키징 시 종속성(Dependencies) 용량 초과 문제를 방지하고 로컬 테스트 용이성을 확보하기 위해, Zip 파일 방식보다 **컨테이너 이미지(Container Image) 배포** 방식을 우선 고려하십시오.
- **[MUST] SAM Local Testing (CLI):** AWS SAM(Serverless Application Model) 기반의 인프라 코드 작성 시 단순 멘탈 시뮬레이션에 의존하지 말고, `run_command`로 `sam validate`를 실행하여 템플릿 문법을 사전 검증하십시오.
- **[Trigger: After Lambda Code Edit] Local Invoke Trigger:** 람다(Lambda) 함수 코드 변경 시 실제 클라우드에 배포하기 전에 `sam local invoke` 또는 `sam local start-api`를 사용하여 로컬 환경에서 함수 동작을 시뮬레이션하고 에러를 확인하십시오.
</aws_serverless_standards>

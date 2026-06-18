<aws_azure_serverless_standard>
# 컨텍스트 모듈: 멀티 클라우드 Serverless 및 Event-driven 아키텍처

## 1. 멀티 클라우드 Serverless 원칙
- **[MUST] Cloud-Native Bridging:** AWS Lambda와 Azure Functions를 멀티 클라우드에 구성할 경우, 두 클라우드 간의 이벤트 브릿징을 위해 AWS EventBridge 및 Azure Event Grid를 활용한 비동기식(Asynchronous) 아키텍처를 제안하십시오.
- **[MUST] Stateless Design:** 서버리스 함수 설계 시 로컬 파일 시스템이나 내부 상태(State)에 의존하지 말고 철저히 무상태(Stateless)로 구현하십시오.
- **[MUST] Orchestration:** 복잡한 워크플로우를 단일 함수에 하드코딩하지 말고, AWS Step Functions 또는 Azure Logic Apps를 활용하여 논리적으로 분리(Decoupling)하십시오.
- **[MUST] Performance Optimization (Cold Start):** 지연 시간(Latency)에 민감한 멀티 클라우드 API 설계 시, 함수(Lambda/Functions)의 콜드 스타트 이슈를 방지하기 위해 Provisioned Concurrency 설정이나 구동이 빠른 런타임(Rust, Go 등)으로의 전환 등 성능 최적화 대안을 반드시 함께 제시하십시오.

## 2. 안정성 및 오류 처리
- **[MUST] Failure Handling & Retry:** 모든 비동기 이벤트 트리거 룰(EventBridge, Kinesis, Event Grid 등)에는 메시지 유실을 방지하기 위해 **반드시 Dead Letter Queue (DLQ), On-Failure Destinations 또는 스트림 에러 제어(예: BisectBatchOnFunctionError)**를 구성하고 재시도(Retry) 정책을 정의하십시오.
- **[MUST] API Security:** AWS API Gateway 또는 Azure API Management 제안 시 퍼블릭 오픈을 엄격히 금지하고, 통합 인증(OIDC/OAuth2) 파이프라인을 필수 구성하십시오.

## 3. 로컬 테스트 및 배포
- **[MUST] Local Emulation:** 서버리스 코드 리뷰 시 클라우드 전용 객체(예: `event`, `context`) 구조체를 명확히 검토하고, 오류 가능성이 보일 시 관련된 SDK 로컬 검증 도구 활용을 제안하십시오.
- **[PREFER] Container Artifact:** 종속성 관리를 일원화하기 위해 AWS Lambda와 Azure Functions 배포 패키징으로 컨테이너 이미지(Container Image) 방식을 적극 권장하십시오.
</aws_azure_serverless_standard>

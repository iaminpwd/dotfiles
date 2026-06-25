<domain_specific_rules instruction="Apply these rules ONLY when working with Azure Functions, Logic Apps, Event Grid, or event-driven architecture.">
<serverless_standard role="Senior Cloud Architect" priority="high">
# 컨텍스트 모듈: Serverless 및 Event-driven 아키텍처

## 1. Serverless 설계 원칙
- **[PREFER] Event-driven:** Service Bus, Event Grid, **Event Hubs** 등을 활용한 비동기식(Asynchronous) 이벤트 기반 아키텍처를 최우선으로 제안하십시오.
- **[MUST] State Isolation:** Azure Functions 함수 설계 시 반드시 무상태(Stateless)로 설계하고 필요한 데이터는 Cosmos DB 등 외부 저장소를 활용하도록 구성하십시오.
- **[MUST] Orchestration:** 복잡한 비즈니스 로직(Workflow) 구현 시 Azure Durable Functions 또는 Logic Apps를 활용한 오케스트레이션을 적극 제안하십시오.
- **[MUST] Performance Optimization (Cold Start):** 지연 시간(Latency)에 민감한 API 설계 시, 콜드 스타트 이슈를 극복하기 위해 Premium Plan 사전 준비된 인스턴스(Pre-warmed instances) 설정이나 구동이 빠른 런타임(Rust, Go 등) 전환을 필수 대안으로 제시하십시오.

## 2. 보안 및 오류 처리
- **[MUST] Failure Handling & Retry:** 모든 비동기 Azure Functions 호출 및 이벤트 트리거(Service Bus, Event Grid, **Event Hubs** 등)에는 메시지 처리의 신뢰성을 보장하기 위해 **Dead Letter Queue (DLQ), On-Failure Destinations 또는 스트림 에러 제어**를 구성하고 재시도(Retry) 정책을 명시하십시오.
- **[MUST] API Security:** API Management 제안 시 반드시 Entra ID 인증, Azure AD B2C, 또는 Custom Authorizer를 필수 구성 요소로 포함하여 퍼블릭 접근을 통제하십시오.

### 비동기 오류 제어 예시 (Few-Shot Examples)
<examples>
<example>
[Good]
```json
{
  "version": "2.0",
  "retry": {
    "strategy": "fixedDelay",
    "maxRetryCount": 3,
    "delayInterval": "00:00:10"
  }
}
```
</example>
<example>
[Bad]
# maxRetryCount 설정 누락 (무한 재시도 위험)
# Service Bus DLQ 등 누락 (메시지 유실)
</example>
</examples>

- **[Trigger: Serverless Deployed] 자가 비판 (Self-Critique):** 서버리스 아키텍처(Azure Functions, Service Bus, Event Grid 등) 구성을 제안/수정한 직후, 스스로 `<self_critique>` 태그를 열어 **비동기 이벤트 처리 실패 시 무한 재시도(Infinite Loop) 발생 가능성 및 Dead Letter Queue (DLQ) 누락으로 인한 메시지 영구 유실 가능성**을 집중 비판하십시오.

## 3. 배포 및 패키징
- **[PREFER] Container Image:** 배포 패키징 시 종속성(Dependencies) 용량 한계를 극복하고 로컬 테스트 용이성을 확보하기 위해, Zip 파일 방식보다 **컨테이너 이미지(Container Image) 배포** 방식을 우선 고려하십시오.
- **[MUST] Func Local Testing (CLI):** Azure Functions 기반의 서버리스 프로젝트 작성 시 반드시 `run_command`로 `func start`를 실행하여 템플릿 문법을 사전 검증하십시오.
- **[MUST] Azure SDK Safety:** Python Azure SDK 기반의 코드 작성 및 리뷰 시, 대량 조회용 `ItemPaged` 사용 및 `HttpResponseError` 예외 처리 안정성 확보를 깐깐하게 검토하십시오.
- **[Trigger: After Azure Functions Code Edit] 로컬 인보크 테스트 (Local Invoke Trigger):** 수정된 Azure Functions 코드를 클라우드에 배포하기 전, 반드시 `run_command`를 통해 `func start`를 실행하여 로컬에서 함수를 시뮬레이션(테스트)하십시오.
</serverless_standard>
</domain_specific_rules>

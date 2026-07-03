---
role: Senior Cloud Architect
priority: high
trigger: Apply these rules ONLY when working with Azure Functions, API Management, Logic Apps, or event-driven architecture.
---
# 컨텍스트 모듈: Serverless 및 Event-driven 아키텍처

## 1. Serverless 설계 원칙
- **[PREFER] Event-driven:** Service Bus, Event Grid, **Event Hubs** 등을 활용한 비동기식(Asynchronous) 이벤트 기반 아키텍처를 최우선으로 제안하십시오.
- **[MUST] State Isolation:** Azure Functions 설계 시 반드시 무상태(Stateless)로 설계하고 필요한 데이터는 Cosmos DB 등 외부 저장소를 활용하도록 구성하십시오.
- **[MUST] Orchestration:** 복잡한 비즈니스 로직(Workflow) 구현 시 Azure Logic Apps 또는 Durable Functions를 활용한 오케스트레이션을 적극 제안하십시오.
- **[MUST] Performance Optimization (Cold Start):** 지연 시간(Latency)에 민감한 API 설계 시, 콜드 스타트 이슈를 극복하기 위해 Premium 플랜(Always Ready 인스턴스) 설정이나 구동이 빠른 런타임(Rust, Go 등) 전환을 필수 대안으로 제시하십시오.

## 2. 보안 및 오류 처리
- **[MUST] Failure Handling & Retry:** 모든 비동기 Azure Functions 호출 및 이벤트 트리거(Service Bus, Event Grid 등)에는 메시지 처리의 신뢰성을 보장하기 위해 **Dead Letter Queue (DLQ) 및 재시도(Retry) 정책**을 명확히 구성하십시오.
- **[MUST] API Security:** API Management 제안 시 반드시 Azure RBAC 인증, Microsoft Entra ID(Azure AD) 연동, 또는 Azure Functions 연동(Custom Authorization)을 필수 구성 요소로 포함하여 퍼블릭 접근을 통제하십시오.

### 비동기 오류 제어 예시 (Few-Shot Examples)
<examples>
<example>
[Good]
```hcl
resource "azurerm_eventgrid_event_subscription" "example" {
  name  = "example-subscription"
  scope = azurerm_resource_group.example.id
  
  dead_letter_endpoint {
    storage_blob_dead_letter_destination {
      storage_account_id          = azurerm_storage_account.dlq.id
      storage_blob_container_name = "dlq"
    }
  }
  
  retry_policy {
    max_delivery_attempts = 2
    event_time_to_live    = 60
  }
}
```
</example>
<example>
[Bad]
# max_delivery_attempts 설정 누락 (무한 재시도 위험)
# DLQ(dead_letter_endpoint) 누락 (메시지 유실)
</example>
</examples>

- **[Trigger: Serverless Deployed] 자가 비판 (Self-Critique):** 서버리스 아키텍처(Azure Functions, Service Bus, Event Grid 등) 구성을 제안/수정한 직후, 스스로 `<self_critique>` 태그를 열어 **비동기 이벤트 처리 실패 시 무한 재시도(Infinite Loop) 발생 가능성 및 Dead Letter Queue (DLQ) 누락으로 인한 메시지 영구 유실 가능성**을 집중 비판하십시오.

## 3. 배포 및 패키징
- **[PREFER] Container Image:** 배포 패키징 시 종속성(Dependencies) 용량 한계를 극복하고 로컬 테스트 용이성을 확보하기 위해, Zip 파일 방식보다 **컨테이너 이미지(Container Image) 배포** 방식을 우선 고려하십시오.
- **[MUST] Bicep Validation (CLI):** Bicep 기반의 인프라 코드 작성 시 반드시 `run_command`로 `az bicep build -f <특정_템플릿_파일>`을 실행하여 템플릿 문법을 사전 검증하십시오.
- **[MUST] Azure SDK Safety:** Azure SDK for Python 기반의 Azure Functions 코드 작성 및 리뷰 시, 대량 조회용 페이징(Paging) 처리 및 `azure.core.exceptions` 예외 처리의 안정성 확보를 깐깐하게 검토하십시오.
- **[Trigger: After Azure Functions Code Edit] 로컬 인보크 테스트 (Local Invoke Trigger):** 수정된 Azure Functions 코드를 클라우드에 배포하기 전, 반드시 `run_command`를 통해 `func start`를 실행하여 로컬에서 함수를 시뮬레이션(테스트)하십시오.

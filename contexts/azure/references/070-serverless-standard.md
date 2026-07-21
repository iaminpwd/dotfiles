---
role: Senior Cloud Architect
priority: high
trigger: Apply these rules ONLY when working with Azure Functions, API Management, Logic Apps, or event-driven architecture.
references:
  - contexts/azure/references/050-iac-standard.md
  - contexts/azure/references/020-security-compliance.md
  - contexts/azure/references/025-cloud-security.md
  - contexts/azure/references/030-finops-optimization.md
---
# 컨텍스트 모듈: Serverless 및 Event-driven 아키텍처

본 모듈은 Azure Functions, API Management, Logic Apps 및 서버리스 기반 이벤트 구동형 아키텍처 설계와 구현 시 적용되는 기술 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] State Isolation:** Azure Functions 설계 시 반드시 무상태(Stateless)로 설계하고, 상태나 지속성 데이터는 Cosmos DB 등 외부 분리 저장소를 활용하도록 하십시오.
- **[MUST] Failure Handling & Retry:** 모든 비동기 Azure Functions 호출 및 이벤트 트리거(Service Bus, Event Grid 등)에는 메시지 처리 신뢰성 확보를 위해 Dead Letter Queue (DLQ) 또는 Event Subscription의 dead_letter_endpoint를 필수 구성하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 이벤트 소스 및 API 게이트웨이 보안
- **[PREFER] Event-driven:** Event Grid, Service Bus, Event Hubs 등을 활용한 비동기식 이벤트 기반 흐름을 최우선 제안하고, 복잡한 비즈니스 로직은 Logic Apps 또는 Durable Functions 오케스트레이션으로 분리하십시오.
- **[MUST] API Security:** API Management 제안 시 반드시 Azure RBAC 인증, Microsoft Entra ID 연동, 또는 Functions API Key 연동을 필수 구성하여 퍼블릭 무단 접근을 차단하십시오.
- **[MUST] Performance Optimization:** 레이턴시 민감 API 설계 시, 콜드 스타트 극복을 위해 Premium 플랜(Always Ready 인스턴스) 설정 또는 Rust/Go 등 빠른 구동 런타임 사용을 대안으로 검토하십시오.
- **[MUST] Throttling Protection:** 다운스트림(DB 등) 자원 과부하를 방지하기 위해 트래픽이 큰 Function App에는 스케일아웃 상한(Function App Scale Limits)을 설정하십시오.

### 2.2 배포 패키징 및 Azure SDK 개발 표준
- **[PREFER] Container Image:** Functions 종속성 용량 한계 극복을 위해 Zip 파일보다 컨테이너 이미지 배포 아키텍처를 우선 제안하십시오.
- **[MUST] Azure SDK Safety:** Python Azure SDK 사용 시, 대량 조회용 Pager 클래스 적용 및 `azure.core.exceptions` 예외 처리를 반드시 포함하십시오.
- **[MUST] API Call Idempotency:** Azure SDK/CLI를 통한 리소스 생성 스크립트 작성 시, 중복 생성을 막기 위해 반드시 고유 식별자(`client-request-id` 헤더 등)를 포함하십시오.
- **[PREFER] Observability Tooling:** 구조화된 로깅, 분산 추적, 커스텀 메트릭 계측을 위해 Application Insights SDK(OpenTelemetry 연동) 사용을 우선 제안하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
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
# max_delivery_attempts 설정 누락 (이벤트 유실 및 무한 루프 위험)
# dead_letter_endpoint 누락 (에러 시 유실된 메시지 추적 불가)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** Azure Bicep CLI를 통해 템플릿의 형식이 에러 없이 검증되고, 로컬 시뮬레이션(`func start` 등)을 거쳐 이진(Pass/Fail) 결과를 획득해야 합니다.
- **[MUST] 검증 도구 매핑:** `az bicep build -f <template_file>` 및 `tflint`를 사용하여 서버리스 템플릿과 권한 설정을 점검하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Serverless Deployed] 점검 기준 (절차는 010-azure-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (오류 격리): 비동기 이벤트 처리 실패 시 Dead Letter Queue (DLQ)로 자동 격리(dead_letter_endpoint)되는 경로가 설정되었는가?
  - 기준 2 (보안 통제): API Management의 퍼블릭 엔드포인트에 인증(Entra ID/API Key 등) 장치가 누락 없이 결합되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - Functions의 메모리 및 인스턴스 스케일아웃 제한이 비합리적으로 과도하게 높게 설정되어 리소스 낭비 위험성이 확인될 시 작업을 즉시 중단(Halt & Clarify)하고 최적화를 요청하십시오.
  - Service Bus/Event Grid 비동기 파이프라인에서 DLQ 유실이 확인되고 수동 재처리 복구 계획이 부재할 시 작업을 멈추고 대체 설계를 구현하십시오.

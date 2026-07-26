---
role: Senior K8s Platform Architect
priority: high
trigger: Apply these rules ONLY when designing networking, service mesh, ingress, or network policies.
references:
  - contexts/k8s/references/010-k8s-core.md
  - contexts/k8s/references/070-advanced-security-standard.md
reviewed: 2026-07-21
---
# 컨텍스트 모듈: Enterprise Kubernetes 네트워킹 및 Service Mesh 표준

본 모듈은 Kubernetes 클러스터 내/외부 트래픽 제어, Service Mesh 연동, 네트워크 정책 및 암호화 설계 시 적용되는 기술 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Zero-Trust 기반 인바운드 통제 (Default Deny All):** 네임스페이스 프로비저닝 시, 파드 간 통신(Ingress/Egress)을 기본적으로 차단하는 `Default Deny All` NetworkPolicy를 최우선 선언하십시오.
- **[PREFER] Service Mesh L7 mTLS:** 마이크로서비스 간 인증 및 L7 인가가 필요할 시, Istio/Linkerd 프록시 단에서 상호 인증(mTLS)을 `STRICT` 모드로 강제하는 아키텍처를 적용하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 클러스터 네트워크 트래픽 제어 및 라우팅
- **[MUST] Explicit Allow & Least Privilege:** `Default Deny All` 적용 후, 인가된 트래픽(예: frontend -> backend, Prometheus Scraping)만 명시적으로 허용하는 화이트리스트 정책을 구성하십시오. 범용 IP 대역(0.0.0.0/0) 완전 개방은 배제하고 명시적 대상 서브넷을 지정하십시오.
- **[PREFER] Ingress Standardization:** 외부 진입 트래픽 제어를 위해 Nginx Ingress, AWS ALB Ingress, 또는 Gateway API 단일 진입점을 두고 경로 기반 라우팅(Path-based Routing)을 설계하십시오.
- **[MUST] Egress Control & FQDN Filtering:** 데이터 유출 방지를 위해 Cilium의 FQDN 기반 NetworkPolicy나 Istio Egress Gateway를 활용하여 인가된 외부 도메인(`*.example.com` 등)만 허용하도록 Egress를 제어하십시오.

### 2.2 네트워크 암호화 및 복원력
- **[PREFER] CNI-Level Encryption:** L4 이하의 노드 간 트래픽 스니핑 방어가 주목적일 때, Cilium Transparent Encryption(WireGuard)을 적용하십시오.
- **[PREFER] Traffic Resilience:** 네트워크 지연에 대비하기 위해 Service Mesh가 제공하는 Circuit Breaker, Retry, Timeout 정책을 기본 구성에 결합하십시오.
- **[MUST] Automated Certificate Lifecycle:** Ingress TLS 인증서는 수동 발급 하드코딩을 배제하고, `cert-manager`를 통해 Let's Encrypt 또는 Vault PKI와 연동해 자동 갱신되도록 하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- Default Deny All NetworkPolicy 선언:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: prod-payment
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```
</example>
<example>
[Bad]
- NetworkPolicy 기본 선언 누락 (네임스페이스 전체가 Ingress/Egress 무방비 오픈 상태로 방치됨)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** NetworkPolicy 매니페스트 린팅 스캔이 에러 없이 통과되고, Ingress 도메인 인증서 갱신 파이프라인의 정의가 검증되어야 합니다.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Before Network Change] 점검 기준 (절차는 010-k8s-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (격리성): 네임스페이스 내 전체 파드가 `Default Deny All` 정책 하에 철저하게 격리되었는가?
  - 기준 2 (복원력): L7 프록시 단에 네트워크 타임아웃 및 재시도 회수 제한 등 안정성 정책이 기입되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 신규 네임스페이스 매니페스트 중 `Default Deny All` NetworkPolicy 선언이 누락되었음이 확인될 시 작업을 즉시 중단(Hard Block)하고 정책을 보완하십시오.
  - Ingress 설정 시 `tls` 영역의 `secretName`에 수동으로 생성한 Let's Encrypt 인증서(1회성)가 바인딩된 코드가 감지되면 즉시 작업을 멈추고 `cert-manager` 연동으로 수정을 유도하십시오.

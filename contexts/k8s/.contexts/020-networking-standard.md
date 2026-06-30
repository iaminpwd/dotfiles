---
role: Senior K8s Platform Architect
priority: high
trigger: Apply these rules ONLY when designing networking, service mesh, ingress, or network policies.
---
# 컨텍스트 모듈: Enterprise Kubernetes 네트워킹 및 Service Mesh 표준

## 1. 클러스터 네트워크 트래픽 제어 (Network Policy)
- **[MUST] Zero-Trust 기반 인바운드 통제 (Default Deny All):** 클러스터 보안의 기본은 Zero Trust입니다. 새로운 네임스페이스가 프로비저닝될 때, 해당 네임스페이스 내의 모든 파드 간 통신(Ingress/Egress)을 기본적으로 차단하는 `Default Deny All` NetworkPolicy를 최우선으로 선언하십시오.
- **[MUST] Explicit Allow & Least Privilege:** `Default Deny All` 적용 후, 인가된 트래픽(예: 프론트엔드 -> 백엔드, Prometheus Scraping)만 명시적으로 허용(Allow)하는 화이트리스트 정책을 구성하십시오. 범용 IP 대역(0.0.0.0/0) 개방은 대신 명시적 화이트리스트를 사용하십시오.
- **[Trigger: Before Network Change] 정책 검증 (Policy Validation):** NetworkPolicy 매니페스트를 작성하거나 변경하기 전, 로컬에 `checkov` 또는 `kube-linter`가 있다면 `run_command`로 `checkov -f <특정_파일>` 또는 `kube-linter lint <특정_파일>`을 실행하여 과도한 포트 개방이나 취약한 정책을 사전에 스캐닝하십시오.

## 2. Ingress & Egress 라우팅 (Traffic Management)
- **[MUST] Ingress Standardization:** Kubernetes 외부에서 들어오는 트래픽 처리를 위해 경로 기반 라우팅을 강제합니다. Nginx Ingress Controller, AWS ALB Ingress Controller, 또는 Gateway API와 같은 단일 진입점을 두고 경로 기반 라우팅(Path-based Routing) 아키텍처를 제안하십시오.
- **[MUST] Egress Control & FQDN Filtering:** 컨테이너 침해 시 C2(Command & Control) 서버로의 데이터 유출 방지를 위해, 아웃바운드 트래픽을 철저히 통제하십시오. 단순 IP 필터링을 넘어 Cilium의 FQDN 기반 NetworkPolicy나 Istio Egress Gateway를 활용하여 인가된 도메인(`*.example.com` 등)만 허용하십시오.

## 3. 네트워크 암호화 아키텍처 (Network Encryption & mTLS)
네트워크 암호화 제안 시 아키텍처 목적에 따라 계층을 명확히 구분하십시오:
- **[PREFER] CNI-Level Encryption (WireGuard/IPsec):** L4 이하의 노드 간 물리적 트래픽 스니핑 방어가 주 목적이라면, 애플리케이션 코드를 수정할 필요 없는 투명한 암호화 방식인 Cilium Transparent Encryption(WireGuard)을 제안하십시오.
- **[MUST] Service Mesh L7 mTLS (Istio/Linkerd):** 마이크로서비스 간의 강력한 인증(Identity) 및 L7 레벨 인가(Authorization)가 필요하다면, 프록시 단에서 상호 인증(mTLS)을 `STRICT` 모드로 강제하는 Service Mesh 아키텍처를 우선 제안하십시오.

## 4. 인증서 및 TLS 관리 (TLS & Certificates)
- **[MUST] Automated Certificate Lifecycle:** Ingress의 TLS 인증서를 수동으로 발급하여 Secret에 하드코딩하는 안전한 파이프라인을 구축하십시오. `cert-manager`를 통해 Let's Encrypt(ACME) 또는 사내 Vault PKI와 연동하여 인증서의 발급 및 갱신(Renewal)이 완전 자동화되는 파이프라인을 구축하십시오.
- **[PREFER] Traffic Resilience:** 네트워크 지연 및 단절에 대비해 Service Mesh가 제공하는 Circuit Breaker, Retry, Timeout, Fault Injection 기능을 적극 도입하여 시스템 복원력(Resiliency)을 강화하십시오.
</k8s_networking_standard>

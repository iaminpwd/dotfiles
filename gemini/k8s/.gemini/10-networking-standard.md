# 컨텍스트 모듈: Enterprise Kubernetes 네트워킹 및 Service Mesh 표준

## 1. 클러스터 네트워크 트래픽 제어 (Network Policy)
- **[MUST] Default Deny All:** 클러스터 보안의 기본은 Zero Trust입니다. 새로운 네임스페이스가 프로비저닝될 때, 해당 네임스페이스 내의 모든 파드 간 통신(Ingress/Egress)을 차단하는 `Default Deny All` NetworkPolicy를 기본으로 적용하도록 강제하십시오.
- **[MUST] Explicit Allow:** `Default Deny All` 적용 이후, 웹 서비스(Frontend)에서 백엔드(Backend)로의 통신이나 모니터링 수집기(Prometheus)의 Scraping 통신 등 꼭 필요한 트래픽만 라벨(Label) 셀렉터를 기반으로 허용(Allow)하는 명시적 화이트리스트(Whitelist) 정책을 작성하십시오.

## 2. Ingress & Egress 라우팅 (Traffic Management)
- **[MUST] Ingress Standardization:** Kubernetes 외부에서 들어오는 트래픽을 처리할 때 원시 `NodePort`나 개별 `LoadBalancer` 생성을 남발하지 마십시오. Nginx Ingress Controller, AWS ALB Ingress Controller, 또는 Istio IngressGateway와 같은 단일 진입점을 두고 `Ingress` (또는 Gateway API) 리소스를 통해 경로 기반 라우팅을 제안하십시오.
- **[MUST] Egress Control & FQDN Filtering:** 컨테이너가 해킹당했을 때 외부 악성 서버로 통신하는 것을 막기 위해, 클러스터 외부로 향하는 트래픽을 통제하십시오. 단순히 IP 기반 제어가 아닌 Cilium NetworkPolicy의 FQDN 필터링이나 Istio Egress Gateway를 활용하여 `*.github.com` 등 인가된 도메인으로만 아웃바운드를 허용하십시오.

## 3. 네트워크 암호화 아키텍처 (Network Encryption)
네트워크 암호화 제안 시 아키텍처의 목적에 따라 다음 두 가지 계층 중 하나를 명확히 구분하여 제안하십시오 (중복 적용 지양):
- **[PREFER] CNI-Level Encryption (WireGuard/IPsec):** L4 이하의 물리적/논리적 네트워크 스니핑 방어가 주 목적인 경우, 애플리케이션 투명성을 보장하는 Cilium Transparent Encryption(WireGuard)을 제안하십시오.
- **[MUST] Service Mesh L7 mTLS (Istio/Linkerd):** L7 수준의 마이크로서비스 간 인증(Identity) 및 권한 부여가 목적이라면, 프록시(Envoy) 단에서 상호 TLS(mTLS)를 `STRICT` 모드로 적용하도록 가이드하십시오.

## 4. 인증서 및 TLS 관리 (TLS & Certificates)
- **[MUST] Automated Certificate Lifecycle:** Ingress TLS 인증서를 수동으로 발급하고 Secret에 넣는 방식을 금지합니다. `cert-manager`를 클러스터에 배포하고, Let's Encrypt (ACME)나 사내 자체 서명 인증기관(Vault PKI 등)과 연동하여 인증서의 발급 및 갱신(Renewal)이 자동화되도록 아키텍처를 구성하십시오.
- **[PREFER] Traffic Resilience:** 장애 전파를 막기 위해 Service Mesh의 Circuit Breaker, Retry, Timeout 정책을 적극 활용하십시오.

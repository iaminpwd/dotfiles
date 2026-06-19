<k8s_advanced_security_standard>
# 컨텍스트 모듈: Enterprise Kubernetes 고급 보안 및 런타임 보호 표준

## 1. 런타임 보안 (Runtime Security)
- **[MUST] Threat Detection (Falco / Tetragon):** 파드가 실행 중(Runtime)일 때 발생하는 컨테이너 탈옥(Container Escape), 인가되지 않은 프로세스 실행, 민감한 디렉토리(/etc/shadow 등) 읽기 등 악의적 행위를 탐지하기 위해 **Falco** 또는 **Cilium Tetragon**(eBPF 기반) 솔루션을 DaemonSet으로 배포하는 아키텍처를 필수로 포함하십시오.
- **[MUST] Read-Only Root Filesystem:** 보안이 크리티컬한 워크로드의 매니페스트에는 `securityContext.readOnlyRootFilesystem: true`를 강제하여 파드 침해 시 해커가 악성 바이너리를 다운로드하거나 실행 파일을 변조하지 못하도록 원천 차단하십시오. (임시 쓰기 공간은 `emptyDir` 마운트로 해결)

## 2. 소프트웨어 공급망 보안 (Software Supply Chain Security)
- **[MUST] Image Signature Verification (Cosign / Sigstore):** CI 파이프라인에서 빌드된 이미지가 사내에서 인가된 이미지인지 검증하기 위해, **Cosign**을 활용해 이미지를 서명(Signing)하고 K8s Admission Controller(Kyverno, Connaisseur 등)에서 해당 서명을 검증한 뒤에만 파드 실행을 허용하는 체계를 구축하십시오.
- **[MUST] Vulnerability Admission Control:** Trivy Operator 등을 클러스터에 배포하여, 실행 중인 컨테이너뿐만 아니라 새로 배포되려 하는 이미지에 심각한(CRITICAL) CVE 취약점이 있을 경우 K8s API 서버 단에서 생성(Create) 및 갱신(Update) 요청을 거부(Deny)하도록 동적 어드미션 통제(Dynamic Admission Control) 정책을 설정하십시오.
- **[Trigger: Security Scan Completion] Security Audit Report (보안 감사 보고서):**
  > When a runtime/image vulnerability scan (audit) based on Trivy Operator or Falco is performed, you MUST summarize the security violations and mitigation guides as a Markdown table in the dedicated `security-audit-report.md` artifact.
</k8s_advanced_security_standard>

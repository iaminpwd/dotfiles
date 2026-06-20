<k8s_advanced_security_standard>
# 컨텍스트 모듈: Enterprise Kubernetes 고급 보안, Supply Chain 및 런타임 보호 표준

## 1. 런타임 보안 방어 (Runtime Security)
- **[MUST] Threat Detection (Falco / Tetragon):** 파드가 이미 실행 중인(Runtime) 상태에서 벌어지는 컨테이너 탈옥(Escape), 비정상적 네트워크 리슨, 민감 디렉토리 읽기 등을 방어하기 위해 **Falco** 또는 eBPF 기반의 **Cilium Tetragon**과 같은 능동 탐지 솔루션을 DaemonSet으로 배포하는 아키텍처를 강제하십시오.
- **[MUST] Read-Only Root Filesystem:** 보안 횡단 관심사(Cross-cutting concern)로, 모든 컨테이너 워크로드의 SecurityContext에 `readOnlyRootFilesystem: true`를 선언하십시오. 공격자가 침투하더라도 악성 셸 스크립트나 바이너리를 다운로드하지 못하게 파일 시스템 레벨에서 원천 봉쇄해야 합니다. (로깅 등 임시 쓰기는 `emptyDir` 마운트로 우회)
- **[MUST] Dropping Capabilities:** 기본 컨테이너 Capabilities(`ALL`)를 전면 Drop하고, 애플리케이션 실행에 필수 불가결한 최소한의 권한(`NET_BIND_SERVICE` 등)만 `add` 블록에 명시적으로 추가하십시오.

## 2. 소프트웨어 공급망 보안 (Software Supply Chain Security)
- **[MUST] Image Signature Verification (Sigstore/Cosign):** 파이프라인에서 컨테이너 이미지가 빌드될 때 **Cosign**을 통해 서명(Signing)을 남기고, K8s 클러스터 내의 Admission Controller(Kyverno 등)에서 해당 서명의 유효성을 검증(Verify) 통과한 이미지에 한해서만 파드 프로비저닝을 허용하는 무결성 체계를 구축하십시오.
- **[MUST] Vulnerability Admission Control:** 배포 직전 이미지에 심각도 CRITICAL 수준의 CVE 취약점이 포함되어 있을 경우 K8s API 서버 단에서 객체 생성 자체를 거부(Deny)하도록 Trivy Operator나 OPA Gatekeeper를 기반으로 동적 통제 정책을 강제하십시오.
- **[Trigger: Code Review / Security Scan] 네이티브 스캐닝 및 보고서 생성:**
  > 사용자가 매니페스트 보안 리뷰를 요청하거나 보안 구성을 완료하면, 로컬 터미널에 설치된 `trivy` (예: `trivy image <특정_이미지>`, `trivy fs <특정_경로>`, `trivy k8s <특정_리소스>`) 명령어를 `run_command`로 즉시 실행하여 실질적인 취약점 존재 여부를 확인하십시오. 스캔이 완료되면 발견된 위반 내역과 완화 가이드를 전용 산출물 파일인 `security-audit-report.md`에 Markdown 표 형태로 명확히 문서화하십시오.
</k8s_advanced_security_standard>

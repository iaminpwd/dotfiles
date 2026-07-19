---
role: Senior K8s Platform Architect
priority: high
trigger: Apply these rules ONLY when designing advanced security, container supply chains, or threat detection.
references:
  - contexts/k8s/references/010-k8s-core.md
  - contexts/k8s/references/020-networking-standard.md
---
# 컨텍스트 모듈: Enterprise Kubernetes 고급 보안, Supply Chain 및 런타임 보호 표준

본 모듈은 Kubernetes 클러스터 런타임 보안, 컨테이너 이미지 공급망 검증 및 위협 탐지 아키텍처 수립 시 적용되는 기술 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Threat Detection:** 실행 중인(Runtime) 컨테이너의 탈옥(Escape)이나 의심스러운 시스템 콜을 실시간 방어하도록 eBPF 기반의 Cilium Tetragon 또는 Falco를 DaemonSet으로 배포하십시오.
- **[MUST] Read-Only Root Filesystem:** 악성 셸 스크립트 다운로드 및 디스크 파일 오염을 차단하기 위해, 컨테이너 `securityContext` 내에 `readOnlyRootFilesystem: true` 지정을 의무화하십시오. (쓰기가 필요한 임시 경로는 `emptyDir` 마운트로 격리 우회하십시오)
- **[MUST] Image Signature Verification:** 빌드 시 Cosign을 통해 컨테이너 이미지에 서명을 기입하고, Kyverno/OPA Gatekeeper 등의 Admission Controller에서 서명이 통과된 검증 이미지에 한해서만 배포를 승인하도록 설계하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 런타임 보안 방어 및 최소 권한
- **[MUST] Dropping Capabilities:** 최소 권한 원칙(PoLP)에 따라 컨테이너 기본 Capabilities(`ALL`)를 비활성화(`drop`)하고, 필수적인 특수 권한(`NET_BIND_SERVICE` 등)만 `add` 블록에 명시적으로 최소 기재하십시오.

### 2.2 소프트웨어 공급망 보안
- **[MUST] Vulnerability Admission Control:** 배포 직전 이미지에 심각도 CRITICAL 수준의 CVE 취약점이 포함되어 있을 경우 Kubernetes API 서버 단에서 객체 생성 자체를 거부(Deny)하도록 Trivy Operator나 OPA Gatekeeper를 기반으로 동적 통제 정책을 구성하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- 보안 SecurityContext 선언 예시:
```yaml
spec:
  containers:
  - name: secure-app
    image: secure-registry.azurecr.io/app:v1.0.0
    securityContext:
      readOnlyRootFilesystem: true
      runAsNonRoot: true
      runAsUser: 10001
      allowPrivilegeEscalation: false
      seccompProfile:
        type: RuntimeDefault
      capabilities:
        drop:
        - ALL
        add:
        - NET_BIND_SERVICE
```
</example>
<example>
[Bad]
- `readOnlyRootFilesystem: false` 또는 해당 설정 누락 (공격자의 런타임 악성코드 바이너리 설치 위험 노출)
- `runAsNonRoot: false` 또는 root 사용자 실행 방치 (컨테이너 이탈 및 노드 루트 권한 탈취 안티패턴)
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** `trivy`를 통한 취약점 스캔 분석 결과가 에러 없이 출력되고, 발견된 위반 내역과 조치 권고가 포함된 `security-audit-report.md` 작성이 완료되어야 합니다.
- **[MUST] 검증 도구 매핑:** `trivy k8s` 또는 `trivy image` CLI를 실행하여 컨테이너 이미지와 매니페스트 파일의 보안 취약점을 정량적으로 스캔하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Code Review / Security Scan] 도메인 자가 채점:** 보안 설정을 작성하거나 수정한 직후, 스스로 `<self_critique>` 태그를 열어 아래 2가지 기준으로 1~5점 자가 채점을 수행하고 사유를 명시하십시오. (두 기준 모두 5점 만점일 때만 작업을 완료하십시오)
  - 기준 1 (컨테이너 격리성): 컨테이너가 Root 권한 없이 가동되며 기본 OS Capability가 완벽하게 드롭(`drop: [ALL]`)되었는가?
  - 기준 2 (이미지 신뢰성): 빌드/배포 단계에서 서명(Cosign) 유효성이 보증되어 비인증 이미지 배포가 완벽하게 통제되는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - K8s 파드/배포판 매니페스트 내에 `readOnlyRootFilesystem` 속성이 `false`로 주입되었거나 `runAsNonRoot` 설정이 누락되어 배포가 준비된 상태가 감지되면 즉시 작업을 중단(Halt & Clarify)하고 가드레일을 주입하십시오.
  - Trivy 스캔을 통해 CVE 취약점 중 Critical 등급의 위반 항목이 감지되고 보안 팀 예외 승인(Ignore File)이 부재할 시 즉시 작업을 멈추고 대체 이미지를 제안하십시오.

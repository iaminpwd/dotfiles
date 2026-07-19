---
role: Senior Cloud Architect
priority: high
trigger: Apply these rules ONLY when working with Kubernetes, AKS, Helm, or container orchestration.
references:
  - contexts/azure/references/050-iac-standard.md
  - contexts/azure/references/020-security-compliance.md
  - contexts/azure/references/025-cloud-security.md
  - contexts/azure/references/030-finops-optimization.md
---
# 컨텍스트 모듈: Kubernetes (AKS) 특화 표준

본 모듈은 Azure AKS 클러스터 설계, 컨테이너 오케스트레이션 및 Helm 패키지 배포 시 적용되는 기술 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Least Privilege (Workload Identity):** AKS 워크로드(Pod)에 Azure 리소스 접근 권한을 부여할 때 반드시 Azure Workload Identity를 적용하여 최소 권한을 달성하십시오.
- **[MUST] Envelope Encryption (Prod):** 프로덕션 AKS 클러스터의 K8s Secret에는 반드시 Azure Key Vault(AKV)와 연동한 봉투 암호화(Envelope Encryption)를 적용하십시오. 개발/테스트 클러스터에는 적용을 권장하되, 프로덕션 코드로 포함되지 않도록 주의하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 AKS 클러스터 및 노드 구성
- **[PREFER] Node Security:** AKS 노드 풀 구성 시 컨테이너 실행에 최적화되고 최소화된 Azure Linux 컨테이너 호스트 OS 사용을 우선 제안하십시오.

### 2.2 공통 K8s 코어 룰 참조
- **[MUST] Reference Generic K8s Rules:** 쿠버네티스 공통 기능(네트워크, 스토리지, 파드 생명주기, GitOps 등) 작업 시, 반드시 홈 디렉토리($HOME) 내에 기 설정된 `~/dotfiles/contexts/k8s/SKILL.md` 파일을 절대 경로로 조립하여 먼저 읽고(View), 그 안에 명시된 라우팅 가이드에 따라 `references/` 하위의 적절한 코어 룰을 참조하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- Workload Identity 적용: ServiceAccount의 `metadata.annotations`에 `azure.workload.identity/client-id`를 연결하여 파드에 Federated Identity를 주입하십시오.
</example>
<example>
[Bad]
- 워커 노드 VM IAM에 과도한 권한 위임: "파드가 Blob Storage에 접근해야 하므로 AKS Managed Identity의 리소스 그룹 권한에 Owner 역할을 직접 추가하겠습니다."
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 생성될 K8s 매니페스트 파일이나 Helm 차트의 린트 검사가 경고 없이 패스되고, API 리소스 스키마가 대상 AKS 버전에 유효함이 검증되어야 합니다.
- **[MUST] 검증 도구 매핑:** `kube-linter` 또는 `helm lint`를 사용하여 매니페스트 및 차트 파일의 정적 보안 결함을 스캔하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: AKS Config Proposed] 도메인 자가 채점:** AKS 클러스터나 워크로드 설계를 제안한 직후, 스스로 `<self_critique>` 태그를 열어 아래 2가지 점검 기준으로 1~5점 채점을 수행하고 사유를 명시하십시오. (두 기준 모두 5점 만점일 때만 작업을 승인 요청하십시오)
  - 기준 1 (워크로드 권한 격리): VM Agent Pool Identity 대신 Workload Identity가 개별 파드 계정 단위로 완벽히 매핑되었는가?
  - 기준 2 (보안 통제): 클러스터 API Endpoint가 퍼블릭 차단(Private Cluster) 또는 승인된 IP 범위 기반으로 격리되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - K8s 매니페스트 중 `securityContext` 내에 `privileged: true`가 감지되거나 `hostNetwork: true` 등 호스트 격리를 위반하는 위험 사양이 감지될 경우, 이를 일반 Pod 계정 및 네트워크 폴리시(NetworkPolicy)로 격리하거나 작업을 즉시 중단(Hard Block)하고 대안 설계를 요구하십시오.
  - Key Vault Envelope Encryption 연동 없이 기본 평문 base64 Secret 저장 방식으로 프로덕션 코드가 설계되었을 시 즉시 작업을 멈추고 보안 수정을 적용하십시오.

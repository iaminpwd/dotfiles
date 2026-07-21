---
role: Senior Cloud Architect
priority: high
trigger: Apply these rules ONLY when working with Kubernetes, EKS, Helm, or container orchestration.
references:
  - contexts/aws/references/050-iac-standard.md
  - contexts/aws/references/020-security-compliance.md
  - contexts/aws/references/025-cloud-security.md
  - contexts/aws/references/030-finops-optimization.md
---
# 컨텍스트 모듈: Kubernetes (EKS) 특화 표준

본 모듈은 AWS EKS 클러스터 설계, 컨테이너 오케스트레이션 및 Helm 패키지 배포 시 적용되는 기술 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Least Privilege (Pod Identity/IRSA):** EKS 워크로드(Pod)에 AWS 리소스 접근 권한을 부여할 때 EKS Pod Identity를 우선 적용하여 최소 권한을 달성하십시오. Pod가 타 AWS 계정의 리소스에 접근해야 하는 교차 계정(Cross-Account) 시나리오에서만 IAM Roles for Service Accounts (IRSA)를 대안으로 사용하십시오.
- **[MUST] Envelope Encryption (Prod):** 프로덕션 EKS 클러스터의 K8s Secret에는 반드시 AWS KMS와 연동한 봉투 암호화(Envelope Encryption)를 적용하십시오. 개발/테스트 클러스터에는 적용을 권장하되, 프로덕션 배포 매니페스트와는 별도 파일로 분리 관리하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 EKS 클러스터 및 노드 구성
- **[PREFER] Node Security:** EKS 워커 노드 구성 시 컨테이너 실행에 최적화되고 최소화된 Bottlerocket OS 사용을 우선 제안하십시오.
- **[PREFER] Karpenter Autoscaling:** 노드 오토스케일링 구성 시 Cluster Autoscaler보다 워크로드 요구사항(CPU/메모리/아키텍처)에 맞춰 노드를 직접 프로비저닝하는 Karpenter 사용을 우선 제안하십시오.
- **[PREFER] Managed Observability:** 클러스터 메트릭 및 로그 관측 시 자체 Prometheus/Grafana 운영 부담을 줄이기 위해 Amazon Managed Service for Prometheus(AMP) 및 Amazon Managed Grafana(AMG) 사용을 우선 고려하십시오.

### 2.2 공통 K8s 코어 룰 참조
- **[MUST] Reference Generic K8s Rules:** 쿠버네티스 공통 기능(네트워크, 스토리지, 파드 생명주기, GitOps 등) 작업 시, 반드시 홈 디렉토리($HOME) 내에 기 설정된 `~/dotfiles/contexts/k8s/SKILL.md` 파일을 절대 경로로 조립하여 먼저 읽고(View), 그 안에 명시된 라우팅 가이드에 따라 `references/` 하위의 적절한 코어 룰을 참조하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- Pod Identity 적용: `aws_eks_pod_identity_association` 리소스로 ServiceAccount와 IAM 역할을 연결하여 파드에 권한을 주입하십시오. (교차 계정 시나리오에서만 ServiceAccount `metadata.annotations`의 `eks.amazonaws.com/role-arn`을 사용하는 IRSA 방식을 적용하십시오.)
</example>
<example>
[Bad]
- 워커 노드 IAM에 과도한 권한 위임: "파드가 S3에 접근해야 하므로 EKS Worker Node의 EC2 Instance Profile에 Admin 권한을 직접 추가하겠습니다."
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 생성될 K8s 매니페스트 파일이나 Helm 차트의 린트 검사가 경고 없이 패스되고, API 리소스 스키마가 대상 EKS 버전에 유효함이 검증되어야 합니다.
- **[MUST] 검증 도구 매핑:** `kube-linter` 또는 `helm lint`를 사용하여 매니페스트 및 차트 파일의 정적 보안 결함을 스캔하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: EKS Config Proposed] 점검 기준 (절차는 010-aws-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (워크로드 권한 격리): 노드 인스턴스 프로파일 대신 Pod Identity(또는 교차 계정 시 IRSA)가 개별 파드 계정 단위로 완벽히 매핑되었는가?
  - 기준 2 (보안 통제): 클러스터 API Endpoint가 퍼블릭 차단(Private Access Only) 또는 화이트리스트 IP 기반으로 격리되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - KMS Envelope Encryption 연동 없이 기본 평문 base64 Secret 저장 방식으로 프로덕션 코드가 설계되었을 시 즉시 작업을 멈추고 보안 수정을 적용하십시오. (`privileged`/`hostNetwork` 등 파드 보안 컨텍스트 일반 위반은 `k8s` 스킬의 중단 조건을 참조하십시오.)

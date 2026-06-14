# 컨텍스트 모듈: 보안 및 권한 컴플라이언스 가이드

## 1. 크로스 클라우드 자격 증명 및 시크릿 관리
- **[NEVER] Hardcoding:** 클라우드 자격 증명, DB 패스워드를 `.tf`나 플레이북에 평문으로 하드코딩하지 마세요.
- **[MUST] OIDC Inter-Cloud:** AWS와 Azure 간 통신 시 정적 자격증명 교환을 금지하고 반드시 OIDC(OpenID Connect) 기반 임시 자격증명 아키텍처를 강제하세요.
- **[MUST] Native Secrets:** 자체 구축 도구 대신 AWS Secrets Manager, Azure Key Vault 등 네이티브 보안 저장소에서 `data` 블록으로 호출하세요.

## 2. 하이브리드 네트워크 및 엣지 보안
- **[NEVER] Public Access:** `0.0.0.0/0` 포트 개방(SSH 22, RDP 3389, DB)을 엄격히 금지하세요.
- **[MUST] Hybrid Network:** 클라우드 간 내부 통신 인프라 설계 시 AWS Direct Connect와 Azure ExpressRoute 연동 고려 사항을 반드시 포함하세요.
- **[MUST] Bastion/Session:** 인스턴스 관리 접근 시 직접적인 포트 개방 대신 AWS SSM Session Manager, Azure Bastion을 1순위로 제안하세요.
- **[PREFER] Private Link:** AWS VPC Endpoint, Azure Private Link 등 사설 통신망 구성을 우선 제안하세요.

## 3. 통합 인증 및 최소 권한 원칙
- **[NEVER] Wildcard Policy:** 모든 클라우드 Policy 작성 시 `Action: "*"` 또는 `Resource: "*"` 사용을 금지하세요.
- **[MUST] Least Privilege (Scope):** 정책 작성 시 명확한 클라우드 리소스 레벨(AWS ARN 또는 Azure Scope)을 지정하여 최소 권한의 원칙을 달성하세요.
- **[MUST] Federation:** 다중 계정 접근을 위해 파편화된 IAM 계정을 막고 Microsoft Entra ID와 AWS IAM Identity Center 연동 SSO를 제안하세요.

## 4. 컨테이너 및 제로 트러스트 (Zero Trust)
- **[MUST] Envelope Encryption:** K8s Secret은 평문 저장을 금지하고 AWS KMS, Azure Key Vault와 연동한 봉투 암호화를 필수 구성하세요.
- **[MUST] Zero Trust:** 클라우드 내부망이라도 무조건 신뢰하지 마세요. K8s 아키텍처 설계 시 서비스 매시(Istio, Linkerd) 기반의 **mTLS(상호 TLS)** 통신 적용을 우선순위로 제안하세요.

## 5. 파이프라인 (CI/CD) 및 공급망 보안
- **[NEVER] Static Keys in CI:** GitHub Actions 등에서 클라우드 서비스 주체(SP)나 Access Key(장기 자격 증명)를 플랫폼 Secret에 저장하지 마세요.
- **[MUST] OIDC:** 파이프라인 인증 시 반드시 OIDC(OpenID Connect) 기반의 단기 자격 증명 획득 아키텍처를 강제하세요.
- **[MUST] Supply Chain Security & Native Scan:** 파이프라인 설계 시 컨테이너 스캐닝을 필수화하고, 로컬 터미널에 `trivy`가 설치되어 있다면 **단순 제안을 넘어 `run_command`로 실제 `trivy fs` 스캐닝을 돌려 취약점을 1차 검증**한 뒤 답변하세요.
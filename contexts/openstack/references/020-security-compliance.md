---
role: Senior Security Architect
priority: high
trigger: Apply these rules whenever writing, modifying, or auditing OpenStack security groups, Keystone RBAC policies, secrets, or general private cloud infrastructure security.
references:
  - contexts/openstack/references/010-openstack-core.md
reviewed: 2026-07-23
---
# 컨텍스트 모듈: 시크릿 및 핵심 보안 원칙 (Security Core)

본 모듈은 프라이빗 클라우드 보안 거버넌스 준수 및 OpenStack 자격 증명, Keystone RBAC 권한 설계 시 적용되는 핵심 보안 표준 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Least Privilege:** Keystone role assignment 작성 시 반드시 명시적인 프로젝트/도메인 스코프를 지정하여 최소 권한을 부여하십시오. `admin` 역할은 실제로 클라우드 전역 제어가 필요한 주체에만 부여하고, 워크로드에는 `member`/`reader` 등 세분화된 역할을 지정하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 자격 증명 (Secrets) 관리
- **[MUST] 시크릿 외부 저장소 연동 강제:** DB 패스워드 등 민감한 자격 증명은 반드시 Barbican 시크릿 저장소에 저장하고, 코드에서는 secret href(`data` 조회)로 동적 로드하십시오. 애플리케이션 런타임 자격은 `clouds.yaml`이 아닌 Barbican/Castellan을 경유하도록 설계하십시오.
- **[MUST] Sensitive Output:** Terraform Output 중 민감 정보(패스워드, 시크릿 href)는 `sensitive = true`를 선언하십시오.
- **[MUST] Application Credentials:** CI/CD 파이프라인 및 자동화 주체는 사용자 패스워드가 아닌 Keystone Application Credential(만료 시각·역할 범위 제한)을 사용하고, 가능하면 `unrestricted=false`로 트러스트 위임을 차단하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
- 스코프 한정 역할 부여:
```bash
openstack role add --project prd-web --user svc-deployer member
```
- 시크릿 동적 주입:
```hcl
password = data.openstack_keymanager_secret_v1.db_pass.payload
```
</example>
<example>
[Bad]
- 과도한 권한 부여:
```bash
openstack role add --domain default --user svc-deployer admin
```
- 평문 패스워드 노출:
```hcl
password = "SuperSecret123!"
```
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 모든 자격 증명 노출 위반 검사가 무결하게 통과되고, Keystone 역할 범위가 승인된 프로젝트/도메인으로 격리되어야 합니다.
- **[MUST] 검증 도구 매핑:** `trufflehog`를 사용하여 코드 내 시크릿 노출 여부를 자동 검사하고, `checkov` 또는 `tfsec`을 이용하여 보안 규칙 위반을 사전 스캔하십시오. 역할 할당을 신규 작성하거나 변경한 경우, `openstack role assignment list --names`로 의도치 않은 광역/도메인 스코프 부여 여부를 추가로 검증하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: RBAC Policy Created] 점검 기준 (절차는 010-openstack-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (최소 권한): 역할 할당이 도메인/전역 스코프로 부여되어 권한 상승(Privilege Escalation) 가능성이 존재하는가?
  - 기준 2 (자원 제한): role assignment에 명확한 `--project` 스코프가 지정되어 테넌트 격리가 보장되는가?
- **[Trigger: Security Vulnerability Found] 중단 조건 (Halt Conditions):**
  - 자격 증명(패스워드, Application Credential secret 등)이 평문으로 파일이나 주석에 유출되었음이 감지되면 즉시 모든 작업을 중단(Hard Block)하고 유출 상태를 사용자에게 경고하십시오.
  - `admin` 역할이 불필요한 주체에 도메인/전역 스코프로 부여되거나 권한 범위가 과도한 정책 생성이 감지되면 작업을 멈추고 보안 검토를 요청하십시오.

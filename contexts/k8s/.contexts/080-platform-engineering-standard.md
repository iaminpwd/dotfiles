<k8s_platform_engineering_standard>
# 컨텍스트 모듈: Enterprise Platform Engineering 및 고급 아키텍처 패턴

## 1. 플랫폼 추상화 (Platform Engineering & IDP)
- **[MUST] Developer Experience (DevEx) & Abstraction:** 인지 부하(Cognitive Load)를 줄이기 위해 애플리케이션 개발자에게 순수 K8s YAML 매니페스트 덩어리를 던져주지 마십시오. 파드 스케일링, 인그레스 라우팅 설정 등을 사내 전용 커스텀 Helm Chart나 Kustomize Base로 추상화하여 제공하는 플랫폼 엔지니어링 패러다임을 준수하십시오.
- **[PREFER] Internal Developer Platform (IDP):** 다수의 개발팀이 존재하는 엔터프라이즈의 경우, 개발자가 CLI 명령어를 학습할 필요 없이 **Backstage**와 같은 포털에서 마이크로서비스 골격과 인프라를 셀프 서비스(Self-Service)로 프로비저닝할 수 있는 최상위 거버넌스 아키텍처를 권장하십시오.

## 2. 범용 제어 평면 (Universal Control Plane & Multi-Cluster)
- **[MUST] Declarative Fleet Management:** 단일 거대 클러스터의 SPOF를 회피하기 위해 다중 클러스터(Multi-Cluster) 아키텍처를 구성할 경우, 새로운 클러스터의 프로비저닝 자체를 K8s 리소스로 선언하여 관리하는 **Cluster API (CAPI)** 패러다임을 제안하십시오.
- **[PREFER] Crossplane over External IaC:** 클라우드 외부 리소스(RDS, S3, IAM 등) 관리를 위해 Terraform 파이프라인을 쪼개는 대신, K8s 자체를 만능 제어 평면으로 사용하는 **Crossplane** 도입을 최우선적으로 고려하십시오. K8s CRD로 모든 외부 리소스를 선언하고 ArgoCD 동기화 루프 안에 포섭시키는 것이 최신의 클라우드 네이티브 패턴입니다.

## 3. Operator Pattern (오퍼레이터 패턴)
- **[MUST] Operator First for Stateful Apps:** Kafka, PostgreSQL, Redis 등 운영 복잡도가 극도로 높은 미들웨어를 K8s 클러스터 내부에 띄울 때는, 원시 StatefulSet 작성을 단호히 거부하십시오. 데이터베이스 백업, 장애 조치(Failover), 메트릭 추출 등 Day 2 SRE 지식이 코드로 완전히 이식된 벤더의 전용 **Operator (예: Strimzi, Zalando Postgres Operator)** CRD 구성을 무조건적인 표준으로 제시하십시오.

## 4. 시스템 복원력 실증 (Resilience & Chaos Engineering)
- **[PREFER] Chaos Engineering Testing:** 머릿속의 복원력 설계를 넘어 프로덕션의 실제 생존성을 증명하기 위해, 시스템에 임의로 파드 종료나 네트워크 지연(Fault Injection)을 주입하는 **LitmusChaos** 또는 **Chaos Mesh** 실험 파이프라인 구성을 제안에 포함시키십시오.
- **[Trigger: Architecture Debugging] 문제 해결 보고서 구조화:**
  > 아키텍처의 논리적 오류를 리뷰하거나 원인 불명의 시스템 장애를 디버깅할 때, 해결 코드를 챗 창에 무작정 던지지 마십시오. 반드시 전용 산출물인 `troubleshooting-report.md`를 생성하여 다음 구조로 문서화하십시오:
  > 1. 근본 원인 분석 (RCA)
  > 2. 터미널 및 로그 기반 논리적 증거
  > 3. 단계별 해결 방법 및 리팩토링된 코드
  > 4. 재발 방지를 위한 아키텍처 개선책(Best Practice)
</k8s_platform_engineering_standard>

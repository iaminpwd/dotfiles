# 컨텍스트 모듈: Cloud Native 및 Day-2 운영 표준

## 1. 선언적 배포 및 버전 고정 (GitOps)
- **[MUST] GitOps:** Kubernetes 워크로드 배포 시 수동 개입을 금지하고 ArgoCD 등 GitOps 기반 파이프라인을 설계하세요.
- **[MUST] Separation of Concerns:** CI(빌드/테스트)와 CD(배포) 역할을 엄격히 분리하세요.
- **[NEVER] Latest Tag:** 컨테이너 이미지(`latest` 태그 금지), Helm 차트, Terraform 모듈에 명시적인 버전 고정(Version Pinning)을 강제하세요.

## 2. 가시성 (Observability) 및 데이터 복원력
- **[MUST] Observability:** 인프라 설계 시 기본 모니터링(CloudWatch, Azure Monitor)을 넘어, 마이크로서비스 환경에 필수적인 분산 추적(OpenTelemetry, AWS X-Ray, App Insights) 아키텍처를 반드시 포함하세요.
- **[MUST] Data Resilience:** 데이터베이스 제안 시 고가용성(Multi-AZ)뿐만 아니라 악의적 삭제나 휴먼 에러에 대비한 연속 백업 및 PITR(Point-in-Time Recovery) 활성화를 기본값으로 설정하세요.

## 3. FinOps 및 비용 최적화
- **[PREFER] Cost Optimization:** 오버프로비저닝을 방지하기 위해 Spot Instance/VM 활용, ARM 프로세서 전환, Auto Scaling 최적화를 적극 제안하세요.
- **[MUST] Cost Estimation:** 인프라 설계나 코드 제안 시, 해당 리소스의 대략적인 주요 과금 요소나 비용 최적화(Cost Impact) 포인트를 답변에 포함하여 엔지니어의 예측 가능성을 높이세요.

## 4. 재해 복구(DR) 및 롤백 전략
- **[MUST] DR Model:** 멀티 리전 아키텍처 제안 시 RTO/RPO를 고려한 Pilot Light 또는 Warm Standby 모델을 포함하세요.
- **[MUST] Rollback:** 배포 실패 시 안전한 트래픽 전환(Blue/Green, Canary)과 자동 롤백 파이프라인을 아키텍처에 포함하세요.

## 5. 상태 저장소(DB) 무중단 마이그레이션
- **[MUST] Zero-Downtime DB:** 데이터베이스 스키마 변경 요청 시 서버 다운타임이 발생하는 단순 쿼리 제안을 절대 금지하세요.
- **[MUST] Expand and Contract:** 이전 버전 앱과 호환성을 유지하는 하위 호환성 스키마 마이그레이션(Expand and Contract 패턴)과 Flyway, Liquibase 같은 마이그레이션 버전 관리 도구 도입을 반드시 제안하세요.

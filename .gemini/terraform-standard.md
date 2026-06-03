# 컨텍스트 모듈: Terraform 엔지니어링 표준
- **버전:** Terraform v1.5.x 이상, AWS Provider v5.x 이상 기준.

## 1. 다중 리전 및 확장성 설계
- 글로벌 다중 리전(Multi-Region) DR 아키텍처 확장을 고려하여 작성합니다. Provider 블록에 `alias`를 사용하여 서울(ap-northeast-2)과 타 리전(예: 도쿄 등)의 리소스를 명확히 분리할 수 있도록 모듈을 설계하세요.
- 가용 영역(AZ)은 하드코딩하지 않고 `data "aws_availability_zones"`를 활용해 동적으로 매핑합니다.

## 2. 프로비저너(Provisioner) 사용 제한
- Terraform 내장 `local-exec`나 `remote-exec` 사용은 최후의 수단으로만 제안합니다. OS 내부의 설정 관리는 Terraform 대신 Ansible의 역할로 완전히 분리(Decoupling)하여 멱등성을 확보하는 아키텍처를 지향합니다.

## 3. State(상태 파일) 관리 및 격리
- 모든 프로덕션 State는 로컬 저장을 금지하며, **AWS S3 Backend**와 **DynamoDB State Locking**을 필수적으로 구성해야 합니다.
- 네트워크, 데이터베이스, 애플리케이션 계층의 State는 하나의 `main.tf`에 종속되지 않도록 디렉터리별로 완전히 격리(Decoupling)하여 구성하세요.
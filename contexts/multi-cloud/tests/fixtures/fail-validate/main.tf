# 010-multi-cloud-core.md 3절 검증 게이트 재현: terraform validate 가 참조 오류를
# 잡는지 고정한다. 선언되지 않은 변수를 output 이 참조한다.
# 주의: terraform init 이 필요하므로 프로바이더를 쓰지 않는 config 로 구성했다.
# aws 프로바이더를 쓰면 init 이 레지스트리에서 바이너리를 받아야 해서 테스트가
# 네트워크에 의존하게 된다.
terraform {
  required_version = "~> 1.5"
}

output "broken" {
  value = var.never_declared
}

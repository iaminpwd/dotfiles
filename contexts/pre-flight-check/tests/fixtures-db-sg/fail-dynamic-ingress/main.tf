# dynamic "ingress" 로 규칙을 생성하는 흔한 패턴. 블록 이름이 따옴표 안에 있어
# `ingress {` 패턴에는 걸리지 않으므로, 진입 판정이 이 형태를 따로 받지 않으면
# 0.0.0.0/0 개방이 통째로 미탐된다.
resource "aws_security_group" "db" {
  name = "db-sg"

  dynamic "ingress" {
    for_each = var.db_ports
    content {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
}

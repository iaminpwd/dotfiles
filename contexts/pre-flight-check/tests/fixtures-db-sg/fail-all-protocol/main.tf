# 모든 프로토콜을 뜻하는 protocol = "-1". 이때 포트 인자는 0 으로 적는 것이 관례라
# 포트 리터럴 판정에도, 범위 판정에도 걸리지 않는다. 실제로는 DB 포트를 포함해
# 전부 열리므로 위반으로 잡아야 한다.
resource "aws_security_group" "db" {
  name = "db-sg"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

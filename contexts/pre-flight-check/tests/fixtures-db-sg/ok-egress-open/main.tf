# ingress는 WAS SG로 한정하고 egress만 0.0.0.0/0으로 연 정상 구성.
# 문단 단위로 판정하던 예전 로직은 같은 리소스 안의 egress 0.0.0.0/0 때문에 이 구성을
# 위반으로 오탐해 정상 커밋을 막았다. 오탐이 재발하지 않도록 고정한다.
resource "aws_security_group" "db" {
  name = "db-sg"

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.was.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

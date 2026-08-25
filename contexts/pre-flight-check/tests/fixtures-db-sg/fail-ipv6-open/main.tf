# 개방 대역을 IPv6 로만 여는 형태. 예전 검사기는 IPv4 전체 대역 리터럴만 찾아
# 이 구성을 통째로 미탐했다(실측 재현).
resource "aws_security_group" "db" {
  name = "db-sg"

  ingress {
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
    ipv6_cidr_blocks = ["::/0"]
  }
}

# 위 fail-port-range 의 짝. 범위 판정이 "범위가 있으면 무조건 위반"으로 퇴화하면
# DB 포트를 전혀 포함하지 않는 정상 웹 SG 까지 막힌다. 이 구성은 통과해야 한다.
resource "aws_security_group" "web" {
  name = "web-sg"

  ingress {
    from_port   = 80
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

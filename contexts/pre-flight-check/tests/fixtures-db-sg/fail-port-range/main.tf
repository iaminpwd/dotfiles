# 포트를 리터럴로 적지 않고 "범위"로 여는 형태. 전 포트를 인터넷 전체에 개방하므로
# DB 포트만 콕 집어 연 fail-open-cidr 보다 오히려 더 심한 위반인데, 예전 검사기는
# 블록 안에서 포트 숫자 리터럴만 찾아 이 상위집합을 통째로 미탐했다(실측 재현).
resource "aws_security_group" "db" {
  name = "db-sg"

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

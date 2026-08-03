# db-sg-checker.sh 재현: DB 포트(3306)와 0.0.0.0/0 이 같은 블록(빈 줄로 안 나뉜
# 하나의 문단) 안에 함께 있으면 커밋을 막아야 한다.
resource "aws_security_group_rule" "db_ingress" {
  type              = "ingress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.db.id
}

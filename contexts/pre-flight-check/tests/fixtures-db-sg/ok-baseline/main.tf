# db-sg-checker.sh 재현: DB 포트가 특정 보안 그룹(WAS)로만 한정되어 있고, 전체
# 공개 대역은 전혀 다른 블록(웹 SG, HTTPS 포트)에서만 쓰이면 통과해야 한다. 두
# 블록은 빈 줄로 분리되어 있어 awk 의 RS="" 문단 스캔이 서로 다른 레코드로
# 인식해야 한다. (주석 자체에 검사 대상 리터럴 문자열을 쓰지 않는다 — 같은
# 문단에 두 패턴이 우연히 동시 등장해 오탐을 유발하기 때문이다.)
resource "aws_security_group_rule" "db_ingress" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.was.id
  security_group_id        = aws_security_group.db.id
}

resource "aws_security_group_rule" "web_ingress" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web.id
}

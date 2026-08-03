# pre-flight-check.sh validate_finops_costs 재현: RDS 엔진이 표준 지원 종료 후
# Extended Support(연장 지원) 유료 구간에 들어간 버전이면 infracost breakdown
# 결과에 "Extended support" 비용 항목이 잡혀야 하고, 그 문구가 커밋을 막아야 한다.
terraform {
  required_version = "~> 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_db_instance" "legacy" {
  identifier          = "sample-legacy-db"
  engine              = "mysql"
  engine_version      = "5.7"
  instance_class      = "db.t3.medium"
  allocated_storage   = 20
  username            = "admin"
  password            = "changeme123"
  skip_final_snapshot = true
}

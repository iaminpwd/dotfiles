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

# Extended Support 개념 자체가 없는 리소스로 기준선을 잡는다. RDS 엔진 버전으로
# "지원 종료 아님"을 표현하려 했으나, AWS가 Extended Support 대상을 계속 넓혀서
# 특정 마이너 버전에 의존하면 이 픽스처가 시간이 지나면서 저절로 위반 픽스처로
# 변질될 위험이 있었다(2026-08-01 실측: MySQL 8.0도 이미 Extended Support 대상).
resource "aws_s3_bucket" "sample" {
  bucket = "sample-app-artifacts"
}

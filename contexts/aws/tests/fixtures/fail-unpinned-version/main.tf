# 050-iac-standard.md 2.1 Version Pinning 재현: "Terraform 코어 및 Provider
# 버전(required_version, required_providers)은 특정 버전으로 고정". required_version
# 을 제거한 변형이며, tflint terraform_required_version 이 잡아야 한다.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
  default_tags {
    tags = {
      Project     = "sample"
      Environment = "dev"
      CostCenter  = "cc-1000"
    }
  }
}

resource "aws_security_group" "app" {
  name_prefix = "sample-dev-app-"
  description = "sample app security group"
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "https_from_vpn" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS from corporate VPN"
  cidr_ipv4         = var.vpn_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

variable "vpc_id" {
  type        = string
  description = "대상 VPC 식별자"
}

variable "vpn_cidr" {
  type        = string
  description = "사내 VPN CIDR 대역"
}

resource "aws_network_interface" "app" {
  subnet_id       = var.subnet_id
  security_groups = [aws_security_group.app.id]
  description     = "sample app eni"
}

variable "subnet_id" {
  type        = string
  description = "대상 서브넷 식별자"
}

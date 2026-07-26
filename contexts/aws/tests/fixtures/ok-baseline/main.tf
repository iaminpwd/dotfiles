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

# 050-iac-standard.md 4절 중단 조건 재현: "SSH(22포트) 등 민감 포트가 0.0.0.0/0 으로
# 과도하게 개방되는 보안 규칙이 감지되면 즉시 작업을 멈추고 보안 위반을 보고".
# 이 조항이 사람 눈이 아니라 checkov CKV_AWS_24 로 실제 차단되는지 고정한다.
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

resource "aws_security_group" "open_ssh" {
  name_prefix = "sample-dev-ssh-"
  description = "intentionally open ssh"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

variable "vpc_id" {
  type        = string
  description = "대상 VPC 식별자"
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

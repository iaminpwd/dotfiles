# 050-iac-standard.md 2.1 Version Pinning 재현: "Terraform 코어 및 Provider 버전
# (required_version, required_providers)은 특정 버전으로 고정". required_version 을
# 제거한 변형이며, tflint terraform_required_version 이 잡아야 한다.
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "app" {
  name     = "sample-dev-app-rg"
  location = "koreacentral"

  tags = {
    Project     = "sample"
    Environment = "dev"
    CostCenter  = "cc-1000"
  }
}

resource "azurerm_network_security_group" "app" {
  name                = "sample-dev-app-nsg"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name

  security_rule {
    name                       = "allow-https-from-vpn"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = var.vpn_cidr
    destination_address_prefix = "*"
  }

  tags = {
    Project     = "sample"
    Environment = "dev"
    CostCenter  = "cc-1000"
  }
}

variable "vpn_cidr" {
  type        = string
  description = "사내 VPN CIDR 대역"
}

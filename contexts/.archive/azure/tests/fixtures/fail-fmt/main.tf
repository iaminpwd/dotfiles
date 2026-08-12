# 050-iac-standard.md 3절 검증 게이트 재현: pre-flight-check.sh 는 terraform fmt
# -check 를 통과하지 못하면 커밋을 차단한다. 들여쓰기만 어긋뜨린 변형이다.
terraform {
      required_version = "~> 1.5"
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

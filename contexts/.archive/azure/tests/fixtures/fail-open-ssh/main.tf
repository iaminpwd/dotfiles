# 050-iac-standard.md 4절 중단 조건 재현: "SSH(22포트) 등 민감 포트가 0.0.0.0/0 으로
# 과도하게 개방되는 보안 규칙이 감지되면 즉시 작업을 멈추고 보안 위반을 보고".
# 이 조항이 사람 눈이 아니라 checkov 로 실제 차단되는지 고정한다.
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
    name                       = "allow-ssh-from-internet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    Project     = "sample"
    Environment = "dev"
    CostCenter  = "cc-1000"
  }
}

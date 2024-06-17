terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "> 3.0"
    }
    vault = {
      source = "hashicorp/vault"
      version = "> 2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "vault" {
  address = var.vault_addr
  token   = var.vault_token
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_storage_account" "storage" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  depends_on               = [azurerm_resource_group.main]
}

resource "azurerm_storage_container" "container" {
  name                  = var.storage_container_name
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"
  depends_on            = [azurerm_storage_account.storage]
}

resource "azurerm_virtual_network" "vnet" {
  name                = var.virtual_network_name
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_subnet" "subnet" {
  name                 = var.subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

data "external" "check_public_ip" {
  program = ["bash", "${path.module}/check_public_ip.sh", var.resource_group_name, var.public_ip_name]
}

locals {
  public_ip_exists = data.external.check_public_ip.result.exists == "true"
}

data "azurerm_public_ip" "existing" {
  count                = local.public_ip_exists ? 1 : 0
  name                 = var.public_ip_name
  resource_group_name  = var.resource_group_name
}

resource "azurerm_public_ip" "public_ip" {
  count               = local.public_ip_exists ? 0 : 1
  name                = var.public_ip_name
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "nic" {
  name                 = var.network_interface_name
  location             = var.location
  resource_group_name  = var.resource_group_name

  ip_configuration {
    name                          = "myNicConfiguration"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = local.public_ip_exists ? data.azurerm_public_ip.existing[0].id : azurerm_public_ip.public_ip[0].id
  }
}

resource "azurerm_network_security_group" "nsg" {
  name                = var.network_security_group_name
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface_security_group_association" "nsg_association" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_managed_disk" "my_disk" {
  name                 = var.disk_name
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 100
}

resource "azurerm_virtual_machine" "vm" {
  name                  = var.virtual_machine_name
  location              = var.location
  resource_group_name   = var.resource_group_name
  network_interface_ids = [azurerm_network_interface.nic.id]
  vm_size               = "Standard_E2_v5"

  storage_os_disk {
    name              = var.disk_name
    caching           = "ReadWrite"
    create_option     = "Attach"
    managed_disk_id   = azurerm_managed_disk.my_disk.id
    os_type           = "Linux"
  }

  tags = {
    environment = "Development"
  }
}

resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = ">= 3.0"
    }
  }
}

provider "azurerm" {
  features {}
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

resource "null_resource" "wait_for_storage_account" {
  depends_on = [azurerm_storage_account.storage]

  provisioner "local-exec" {
    command = <<EOT
while [ "$(az storage account show --name ${azurerm_storage_account.storage.name} --resource-group ${azurerm_resource_group.main.name} --query "provisioningState" --output tsv)" != "Succeeded" ]; do
  echo "Waiting for storage account to be provisioned..."
  sleep 10
done
EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "azurerm_storage_container" "container" {
  name                  = var.storage_container_name
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"
  depends_on            = [null_resource.wait_for_storage_account]
}

resource "azurerm_virtual_network" "vnet" {
  name                = var.virtual_network_name
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  depends_on          = [azurerm_resource_group.main]
}

resource "azurerm_subnet" "subnet" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
  depends_on           = [azurerm_virtual_network.vnet]
}

data "external" "check_public_ip" {
  program = ["bash", "${path.module}/check_public_ip.sh", var.resource_group_name, var.public_ip_name]
}

locals {
  public_ip_exists = data.external.check_public_ip.result.exists == "true"
}

data "azurerm_public_ip" "existing" {
  count               = local.public_ip_exists ? 1 : 0
  name                = var.public_ip_name
  resource_group_name = var.resource_group_name
  depends_on          = [azurerm_resource_group.main]
}

resource "azurerm_public_ip" "public_ip" {
  count               = local.public_ip_exists ? 0 : 1
  name                = var.public_ip_name
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  depends_on          = [azurerm_resource_group.main]
}

resource "azurerm_network_interface" "nic" {
  name                = var.network_interface_name
  location            = var.location
  resource_group_name = var.resource_group_name
  depends_on          = [azurerm_resource_group.main, azurerm_subnet.subnet]

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
  depends_on          = [azurerm_resource_group.main]

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

  security_rule {
    name                       = "HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTPS"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface_security_group_association" "nsg_association" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
  depends_on                = [azurerm_network_interface.nic, azurerm_network_security_group.nsg]
}

resource "azurerm_virtual_machine" "vm" {
  name                  = var.virtual_machine_name
  location              = var.location
  resource_group_name   = var.resource_group_name
  network_interface_ids = [azurerm_network_interface.nic.id]
  vm_size               = "Standard_E2_v5"
  depends_on            = [azurerm_network_interface.nic]

  os_profile {
    computer_name  = var.virtual_machine_name
    admin_username = var.admin_username
    admin_password = var.admin_password
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  storage_os_disk {
    name              = var.disk_name
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  tags = {
    environment = "Development"
  }
}

resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

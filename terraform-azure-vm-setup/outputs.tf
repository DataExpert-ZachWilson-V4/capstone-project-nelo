output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "virtual_network_name" {
  value = azurerm_virtual_network.vnet.name
}

output "subnet_name" {
  value = azurerm_subnet.subnet.name
}

output "public_ip" {
  value = local.public_ip_exists ? data.azurerm_public_ip.existing[0].ip_address : azurerm_public_ip.public_ip[0].ip_address
}

output "network_interface_name" {
  value = azurerm_network_interface.nic.name
}

output "network_security_group_name" {
  value = azurerm_network_security_group.nsg.name
}

output "managed_disk_name" {
  value = var.disk_name
}

output "virtual_machine_name" {
  value = azurerm_virtual_machine.vm.name
}

output "public_key" {
  value = tls_private_key.example.public_key_openssh
}

output "private_key" {
  value     = tls_private_key.example.private_key_pem
  sensitive = true
}

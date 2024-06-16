output "public_ip" {
  value = local.public_ip_exists ? data.azurerm_public_ip.existing[0].ip_address : azurerm_public_ip.public_ip[0].ip_address
}

output "public_key" {
  value = tls_private_key.example.public_key_openssh
}

output "private_key" {
  value     = tls_private_key.example.private_key_pem
  sensitive = true
}

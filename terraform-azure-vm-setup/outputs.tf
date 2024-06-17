output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "storage_account_name" {
  value = azurerm_storage_account.storage.name
}

output "storage_account_key" {
  value     = azurerm_storage_account.storage.primary_access_key
  sensitive = true
}

output "storage_container_name" {
  value = azurerm_storage_container.container.name
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
  value = azurerm_managed_disk.my_disk.name
}

output "virtual_machine_name" {
  value = azurerm_virtual_machine.vm.name
}

output "postgres_server_name" {
  value = azurerm_postgresql_server.postgres_server.name
}

output "airflow_db_name" {
  value = azurerm_postgresql_database.airflow_db.name
}

output "superset_db_name" {
  value = azurerm_postgresql_database.superset_db.name
}

output "hive_db_name" {
  value = azurerm_postgresql_database.hive_db.name
}

output "mlflow_db_name" {
  value = azurerm_postgresql_database.mlflow_db.name
}

output "haystack_db_name" {
  value = azurerm_postgresql_database.haystack_db.name
}

output "zookeeper_db_name" {
  value = azurerm_postgresql_database.zookeeper_db.name
}

output "kafka_db_name" {
  value = azurerm_postgresql_database.kafka_db.name
}

output "pgadmin_db_name" {
  value = azurerm_postgresql_database.pgadmin_db.name
}

output "trino_db_name" {
  value = azurerm_postgresql_database.trino_db.name
}

output "qdrant_db_name" {
  value = azurerm_postgresql_database.qdrant_db.name
}

output "spark_db_name" {
  value = azurerm_postgresql_database.spark_db.name
}

output "public_key" {
  value = tls_private_key.example.public_key_openssh
}

output "private_key" {
  value     = tls_private_key.example.private_key_pem
  sensitive = true
}
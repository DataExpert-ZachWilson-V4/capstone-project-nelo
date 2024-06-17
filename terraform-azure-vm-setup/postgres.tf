resource "azurerm_postgresql_server" "postgres_server" {
  name                             = var.postgres_server_name
  location                         = var.location
  resource_group_name              = azurerm_resource_group.main.name
  sku_name                         = "GP_Gen5_2"
  storage_mb                       = 5120
  backup_retention_days            = 7
  geo_redundant_backup_enabled     = false
  administrator_login              = var.postgres_admin_username
  administrator_login_password     = var.postgres_admin_password
  version                          = "11"
  ssl_enforcement_enabled          = true

  threat_detection_policy {
    email_account_admins = true
    enabled              = true
    retention_days       = 7
  }

  depends_on = [azurerm_resource_group.main]
}

resource "azurerm_postgresql_database" "airflow_db" {
  name                 = var.airflow_db
  resource_group_name  = azurerm_resource_group.main.name
  server_name          = azurerm_postgresql_server.postgres_server.name
  charset              = "UTF8"
  collation            = "English_United States.1252"
  depends_on           = [azurerm_postgresql_server.postgres_server]
}

resource "azurerm_postgresql_database" "superset_db" {
  name                 = var.superset_db
  resource_group_name  = azurerm_resource_group.main.name
  server_name          = azurerm_postgresql_server.postgres_server.name
  charset              = "UTF8"
  collation            = "English_United States.1252"
  depends_on           = [azurerm_postgresql_server.postgres_server]
}

resource "azurerm_postgresql_database" "hive_db" {
  name                 = var.hive_db
  resource_group_name  = azurerm_resource_group.main.name
  server_name          = azurerm_postgresql_server.postgres_server.name
  charset              = "UTF8"
  collation            = "English_United States.1252"
  depends_on           = [azurerm_postgresql_server.postgres_server]
}

resource "azurerm_postgresql_database" "mlflow_db" {
  name                 = var.mlflow_db
  resource_group_name  = azurerm_resource_group.main.name
  server_name          = azurerm_postgresql_server.postgres_server.name
  charset              = "UTF8"
  collation            = "English_United States.1252"
  depends_on           = [azurerm_postgresql_server.postgres_server]
}

resource "azurerm_postgresql_database" "haystack_db" {
  name                 = var.haystack_db
  resource_group_name  = azurerm_resource_group.main.name
  server_name          = azurerm_postgresql_server.postgres_server.name
  charset              = "UTF8"
  collation            = "English_United States.1252"
  depends_on           = [azurerm_postgresql_server.postgres_server]
}

resource "azurerm_postgresql_database" "zookeeper_db" {
  name                 = var.zookeeper_db
  resource_group_name  = azurerm_resource_group.main.name
  server_name          = azurerm_postgresql_server.postgres_server.name
  charset              = "UTF8"
  collation            = "English_United States.1252"
  depends_on           = [azurerm_postgresql_server.postgres_server]
}

resource "azurerm_postgresql_database" "kafka_db" {
  name                 = var.kafka_db
  resource_group_name  = azurerm_resource_group.main.name
  server_name          = azurerm_postgresql_server.postgres_server.name
  charset              = "UTF8"
  collation            = "English_United States.1252"
  depends_on           = [azurerm_postgresql_server.postgres_server]
}

resource "azurerm_postgresql_database" "trino_db" {
  name                 = var.trino_db
  resource_group_name  = azurerm_resource_group.main.name
  server_name          = azurerm_postgresql_server.postgres_server.name
  charset              = "UTF8"
  collation            = "English_United States.1252"
  depends_on           = [azurerm_postgresql_server.postgres_server]
}

resource "azurerm_postgresql_database" "qdrant_db" {
  name                 = var.qdrant_db
  resource_group_name  = azurerm_resource_group.main.name
  server_name          = azurerm_postgresql_server.postgres_server.name
  charset              = "UTF8"
  collation            = "English_United States.1252"
  depends_on           = [azurerm_postgresql_server.postgres_server]
}

resource "azurerm_postgresql_database" "spark_db" {
  name                 = var.spark_db
  resource_group_name  = azurerm_resource_group.main.name
  server_name          = azurerm_postgresql_server.postgres_server.name
  charset              = "UTF8"
  collation            = "English_United States.1252"
  depends_on           = [azurerm_postgresql_server.postgres_server]
}

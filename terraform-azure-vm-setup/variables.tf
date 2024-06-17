variable "vault_token" {
  description = "Vault token for authentication"
}

variable "vault_addr" {
  description = "Vault address for authentication"
  default     = "http://127.0.0.1:8200"
}

variable "location" {
  description = "The location where resources will be created"
  default     = "East US"
}

variable "resource_group_name" {
  description = "The name of the resource group"
  default     = "nelomlb"
}

variable "public_ip_name" {
  description = "The name of the public IP resource"
  default     = "myPublicIP"
}

variable "admin_username" {
  description = "Admin username for the VM"
  default     = "azureuser"
}

variable "admin_password" {
  description = "Admin password for the VM"
  default     = "P@ssw0rd1234!"
}

variable "postgres_admin_username" {
  description = "PostgreSQL admin username"
  default     = "postgres_admin"
}

variable "postgres_admin_password" {
  description = "PostgreSQL admin password"
  default     = "P@ssw0rd1234!"
}

variable "storage_account_name" {
  description = "The name of the storage account."
  type        = string
  default     = "nelomlb"
}

variable "storage_container_name" {
  description = "The name of the storage container."
  type        = string
  default     = "nelomlb"
}

variable "virtual_network_name" {
  description = "The name of the virtual network"
  default     = "neloVnet"
}

variable "subnet_name" {
  description = "The name of the subnet"
  default     = "neloSubnet"
}

variable "network_security_group_name" {
  description = "The name of the network security group"
  default     = "neloNSG"
}

variable "network_interface_name" {
  description = "The name of the network interface"
  default     = "neloNic"
}

variable "virtual_machine_name" {
  description = "The name of the virtual machine"
  default     = "neloVM"
}

variable "disk_name" {
  description = "The name of the managed disk"
  default     = "neloOsDisk"
}

variable "postgres_server_name" {
  description = "PostgreSQL server name"
  default     = "nelomlb-postgres-server"
}

variable "airflow_db" {
  description = "Name of the Airflow database"
  default     = "airflow"
}

variable "superset_db" {
  description = "Name of the Superset database"
  default     = "superset"
}

variable "hive_db" {
  description = "Name of the Hive database"
  default     = "hive"
}

variable "mlflow_db" {
  description = "Name of the MLflow database"
  default     = "mlflow"
}

variable "haystack_db" {
  description = "Name of the Haystack database"
  default     = "haystack"
}

variable "zookeeper_db" {
  description = "Name of the Zookeeper database"
  default     = "zookeeper"
}

variable "kafka_db" {
  description = "Name of the Kafka database"
  default     = "kafka"
}

variable "pgadmin_db" {
  description = "Name of the pgAdmin database"
  default     = "pgadmin"
}

variable "trino_db" {
  description = "Name of the Trino database"
  default     = "trino"
}

variable "qdrant_db" {
  description = "Name of the Qdrant database"
  default     = "qdrant"
}

variable "spark_db" {
  description = "Name of the Spark database"
  default     = "spark"
}

variable "ssh_public_key" {
  description = "SSH public key for the VM"
  type        = string
}
variable "location" {
  description = "The Azure region"
  type        = string
  default     = "eastus"
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
  default     = "Password1234!"
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

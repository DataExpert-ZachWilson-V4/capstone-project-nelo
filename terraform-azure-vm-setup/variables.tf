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
  default     = "myResourceGroup"
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

variable "postgres_host" {
  description = "PostgreSQL server host name"
  default     = "nelomlb-postgres-server"
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

variable "datalake_store_name" {
  description = "The name of the Data Lake Store."
  type        = string
  default     = "nelomlb"  
}
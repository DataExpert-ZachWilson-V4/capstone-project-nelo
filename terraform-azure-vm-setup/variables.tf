variable "location" {
  description = "The location where resources will be created"
  default     = "East US"
}

variable "resource_group_name" {
  description = "The name of the resource group"
  default     = "myResourceGroup"
}

variable "admin_username" {
  description = "Admin username for the VM"
  default     = "azureuser"
}

variable "admin_password" {
  description = "Admin password for the VM"
  default     = "P@ssw0rd1234!"
}

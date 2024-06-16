#!/bin/bash

# Self-setting execute permissions
if [ ! -x "$0" ]; then
    chmod +x "$0"
fi

# Exit immediately if a command exits with a non-zero status.
set -e

# Load environment variables from .env file
if [ -f .env ]; then
    echo "Loading environment variables from .env file..."
    export $(grep -v '^#' .env | xargs)
fi

# Ensure STORAGE_ACCOUNT_NAME and RESOURCE_GROUP_NAME are set
if [ -z "$STORAGE_ACCOUNT_NAME" ] || [ -z "$RESOURCE_GROUP_NAME" ]; then
    echo "STORAGE_ACCOUNT_NAME or RESOURCE_GROUP_NAME is not set. Please set them in the .env file."
    exit 1
fi

# Directory containing your project
PROJECT_DIR="$(dirname "$0")"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install dependencies if not installed
install_dependencies() {
    if ! command_exists terraform; then
        echo "Terraform is not installed. Installing Terraform..."
        sudo apt-get update
        sudo apt-get install -y gnupg software-properties-common curl
        curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt-get update
        sudo apt-get install -y terraform
    fi

    if ! command_exists az; then
        echo "Azure CLI is not installed. Installing Azure CLI..."
        sudo apt-get update
        sudo apt-get install -y ca-certificates curl apt-transport-https lsb-release gnupg
        curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/microsoft-archive-keyring.gpg > /dev/null
        AZ_REPO=$(lsb_release -cs)
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | sudo tee /etc/apt/sources.list.d/azure-cli.list
        sudo apt-get update
        sudo apt-get install -y azure-cli
    fi

    if ! command_exists sshpass; then
        echo "sshpass is not installed. Installing sshpass..."
        sudo apt-get update
        sudo apt-get install -y sshpass
    fi

    if ! command_exists vault; then
        echo "Vault is not installed. Installing Vault..."
        curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt-get update
        sudo apt-get install -y vault
    fi
}

# Logging function to track the time taken by each step
log_and_time() {
    start_time=$(date +%s)
    echo "Starting: $1"
    eval $1
    end_time=$(date +%s)
    elapsed_time=$((end_time - start_time))
    echo "Completed: $1 in $elapsed_time seconds"
}

# Install dependencies
log_and_time "install_dependencies"

# Check if VAULT_TOKEN is set in .env file
if [ -z "$VAULT_TOKEN" ]; then
    # Start Vault server in dev mode for demonstration purposes
    vault server -dev -dev-root-token-id="root" &

    # Wait for Vault to start
    sleep 10

    # Set Vault environment variables
    export VAULT_TOKEN='root'

    # Generate a new Vault token
    NEW_VAULT_TOKEN=$(vault token create -ttl=1h -field token)

    # Write the new Vault token to the .env file
    echo "VAULT_TOKEN=$NEW_VAULT_TOKEN" >> .env
    export VAULT_TOKEN=$NEW_VAULT_TOKEN
else
    # Export existing VAULT_TOKEN from .env file
    export VAULT_TOKEN
fi

# Login to Azure CLI using Service Principal
echo "Logging into Azure CLI using service principal..."
if az login --service-principal -u "$ARM_CLIENT_ID" -p "$ARM_CLIENT_SECRET" --tenant "$ARM_TENANT_ID"; then
    echo "Successfully logged in to Azure CLI."
else
    echo "Failed to log in to Azure CLI. Check credentials and try again."
    exit 1
fi

# Verify subscription access
echo "Verifying subscription access..."
if [ "$(az account list --query "[?id=='$ARM_SUBSCRIPTION_ID'] | length(@)")" -eq 0 ]; then
    echo "No subscription found with ID $ARM_SUBSCRIPTION_ID. Please check the subscription ID and try again."
    exit 1
else
    echo "Subscription verified."
fi

# Set the Azure subscription
echo "Setting Azure subscription..."
if az account set --subscription "$ARM_SUBSCRIPTION_ID"; then
    echo "Successfully set the subscription."
else
    echo "Failed to set the subscription. Check subscription ID and try again."
    exit 1
fi

# Generate SSH key pair if not exists
if [ ! -f id_rsa ] || [ ! -f id_rsa.pub ]; then
    echo "Generating SSH key pair..."
    ssh-keygen -t rsa -b 4096 -f id_rsa -q -N ""
fi

# Export the SSH public key to an environment variable
export TF_VAR_ssh_public_key=$(cat id_rsa.pub)

# Navigate to the project directory
cd "$PROJECT_DIR"

# Destroy Terraform resources
cd terraform-azure-vm-setup

# Initialize Terraform to ensure dependency lock file is consistent
log_and_time "terraform init"

# Function to destroy resource if it exists
destroy_resource() {
    local resource_type=$1
    local resource_id=$2

    if az resource show --ids "$resource_id" &> /dev/null; then
        echo "$resource_type $resource_id exists. Destroying resource..."
        terraform destroy -auto-approve
    else
        echo "$resource_type $resource_id does not exist."
    fi
}

# Set the resource IDs
RESOURCE_GROUP_ID="/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME"
STORAGE_ACCOUNT_ID="/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME"
VNET_ID="/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.Network/virtualNetworks/$VIRTUAL_NETWORK_NAME"
SUBNET_ID="/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.Network/virtualNetworks/$VIRTUAL_NETWORK_NAME/subnets/$SUBNET_NAME"
NSG_ID="/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.Network/networkSecurityGroups/$NETWORK_SECURITY_GROUP_NAME"
NIC_ID="/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.Network/networkInterfaces/$NETWORK_INTERFACE_NAME"
VM_ID="/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.Compute/virtualMachines/$VIRTUAL_MACHINE_NAME"
DISK_ID="/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.Compute/disks/$DISK_NAME"
POSTGRES_SERVER_ID="/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/$POSTGRES_SERVER_NAME"
CONTAINER_ID="/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME/blobServices/default/containers/$AZURE_CONTAINER"

# Destroy existing resources
log_and_time "destroy_resource azurerm_resource_group.main $RESOURCE_GROUP_ID"
log_and_time "destroy_resource azurerm_storage_account.storage $STORAGE_ACCOUNT_ID"
log_and_time "destroy_resource azurerm_storage_account.datalake $STORAGE_ACCOUNT_ID"
log_and_time "destroy_resource azurerm_virtual_network.vnet $VNET_ID"
log_and_time "destroy_resource azurerm_subnet.subnet $SUBNET_ID"
log_and_time "destroy_resource azurerm_network_security_group.nsg $NSG_ID"
log_and_time "destroy_resource azurerm_network_interface.nic $NIC_ID"
log_and_time "destroy_resource azurerm_virtual_machine.vm $VM_ID"
log_and_time "destroy_resource azurerm_managed_disk.my_disk $DISK_ID"
log_and_time "destroy_resource azurerm_postgresql_server.postgres_server $POSTGRES_SERVER_ID"
log_and_time "destroy_resource azurerm_storage_container.container $CONTAINER_ID"

# Destroy existing PostgreSQL databases
log_and_time "destroy_resource azurerm_postgresql_database.airflow_db /subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/$POSTGRES_SERVER_NAME/databases/$AZURE_AIRFLOW_DB"
log_and_time "destroy_resource azurerm_postgresql_database.superset_db /subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/$POSTGRES_SERVER_NAME/databases/$AZURE_SUPERSET_DB"
log_and_time "destroy_resource azurerm_postgresql_database.hive_db /subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/$POSTGRES_SERVER_NAME/databases/$AZURE_HIVE_DB"
log_and_time "destroy_resource azurerm_postgresql_database.mlflow_db /subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/$POSTGRES_SERVER_NAME/databases/$AZURE_MLFLOW_DB"
log_and_time "destroy_resource azurerm_postgresql_database.haystack_db /subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/$POSTGRES_SERVER_NAME/databases/$AZURE_HAYSTACK_DB"
log_and_time "destroy_resource azurerm_postgresql_database.zookeeper_db /subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/$POSTGRES_SERVER_NAME/databases/$AZURE_ZOOKEEPER_DB"
log_and_time "destroy_resource azurerm_postgresql_database.kafka_db /subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/$POSTGRES_SERVER_NAME/databases/$AZURE_KAFKA_DB"
log_and_time "destroy_resource azurerm_postgresql_database.pgadmin_db /subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/$POSTGRES_SERVER_NAME/databases/$AZURE_PGADMIN_DB"
log_and_time "destroy_resource azurerm_postgresql_database.trino_db /subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/$POSTGRES_SERVER_NAME/databases/$AZURE_TRINO_DB"
log_and_time "destroy_resource azurerm_postgresql_database.qdrant_db /subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/$POSTGRES_SERVER_NAME/databases/$AZURE_QDRANT_DB"
log_and_time "destroy_resource azurerm_postgresql_database.spark_db /subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/$POSTGRES_SERVER_NAME/databases/$AZURE_SPARK_DB"

# Destroy remaining Terraform resources
echo "Destroying remaining Terraform resources..."
log_and_time "terraform destroy -auto-approve"

# Optionally delete the resource group
echo "Deleting resource group $RESOURCE_GROUP_NAME..."
az group delete --name "$RESOURCE_GROUP_NAME" --yes --no-wait

echo "Cleanup complete. All resources have been deleted."

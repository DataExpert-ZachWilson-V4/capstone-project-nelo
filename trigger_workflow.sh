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

# Ensure STORAGE_ACCOUNT_NAME is set
if [ -z "$STORAGE_ACCOUNT_NAME" ]; then
    echo "STORAGE_ACCOUNT_NAME is not set. Please set it in the .env file."
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

# Store the PostgreSQL credentials in Vault . Replace <USERNAME> with your username and <YOUR_PASSWORD_HERE> with your password
log_and_time "vault kv put secret/data/postgres username=\"<USERNAME>\" password=\"<YOUR_PASSWORD_HERE>\""

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

# Navigate to the project directory
cd "$PROJECT_DIR"

# Generate SSH key pair if not exists
if [ ! -f id_rsa ] || [ ! -f id_rsa.pub ]; then
    echo "Generating SSH key pair..."
    ssh-keygen -t rsa -b 4096 -f id_rsa -q -N ""
fi

# Move the SSH key pair to Terraform directory
cp id_rsa* terraform-azure-vm-setup/

# Initialize Terraform
cd terraform-azure-vm-setup
log_and_time "terraform init"

# Function to import resource if it exists
import_resource() {
    local resource_type=$1
    local resource_id=$2

    if az resource show --ids "$resource_id" &> /dev/null; then
        echo "$resource_type $resource_id already exists. Importing to Terraform..."
        terraform import $resource_type "$resource_id"
    fi
}

# Set the resource IDs
RESOURCE_GROUP_ID="/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME"
STORAGE_ACCOUNT_ID="/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME"
VNET_ID="/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.Network/virtualNetworks/myVnet"
SUBNET_ID="/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.Network/virtualNetworks/myVnet/subnets/mySubnet"
NSG_ID="/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.Network/networkSecurityGroups/myNsg"
NIC_ID="/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.Network/networkInterfaces/myNic"
VM_ID="/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.Compute/virtualMachines/myVM"
DISK_ID="/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.Compute/disks/myOsDisk"
POSTGRES_SERVER_ID="/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/nelomlb-postgres-server"

# Import existing resources if they exist
import_resource "azurerm_resource_group.rg" "$RESOURCE_GROUP_ID"
import_resource "azurerm_storage_account.storage" "$STORAGE_ACCOUNT_ID"
import_resource "azurerm_virtual_network.vnet" "$VNET_ID"
import_resource "azurerm_subnet.subnet" "$SUBNET_ID"
import_resource "azurerm_network_security_group.nsg" "$NSG_ID"
import_resource "azurerm_network_interface.nic" "$NIC_ID"
import_resource "azurerm_virtual_machine.vm" "$VM_ID"

# Special handling for existing disk
if az resource show --ids "$DISK_ID" &> /dev/null; then
    echo "Disk $DISK_ID already exists. Using attach option for the VM..."
    terraform import azurerm_managed_disk.my_disk "$DISK_ID"
fi

# Special handling for existing PostgreSQL server
if az resource show --ids "$POSTGRES_SERVER_ID" &> /dev/null; then
    echo "PostgreSQL server $POSTGRES_SERVER_ID already exists. Importing to Terraform..."
    terraform import azurerm_postgresql_server.postgres_server "$POSTGRES_SERVER_ID"

    # Import existing PostgreSQL databases
    import_resource "azurerm_postgresql_database.airflow_db" "/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/nelomlb-postgres-server/databases/airflow"
    import_resource "azurerm_postgresql_database.superset_db" "/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/nelomlb-postgres-server/databases/superset"
    import_resource "azurerm_postgresql_database.hive_db" "/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/nelomlb-postgres-server/databases/hive"
    import_resource "azurerm_postgresql_database.mlflow_db" "/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/nelomlb-postgres-server/databases/mlflow"
    import_resource "azurerm_postgresql_database.haystack_db" "/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/nelomlb-postgres-server/databases/haystack"
    import_resource "azurerm_postgresql_database.zookeeper_db" "/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/nelomlb-postgres-server/databases/zookeeper"
    import_resource "azurerm_postgresql_database.kafka_db" "/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/nelomlb-postgres-server/databases/kafka"
    import_resource "azurerm_postgresql_database.pgadmin_db" "/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/nelomlb-postgres-server/databases/pgadmin"
    import_resource "azurerm_postgresql_database.trino_db" "/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/nelomlb-postgres-server/databases/trino"
    import_resource "azurerm_postgresql_database.qdrant_db" "/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/nelomlb-postgres-server/databases/qdrant"
    import_resource "azurerm_postgresql_database.spark_db" "/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/nelomlb-postgres-server/databases/spark"
fi

# Apply Terraform plan for VM setup
echo "Creating Terraform plan for VM setup..."
log_and_time "terraform plan -parallelism=10 -out=tfplan"

echo "Applying Terraform plan for VM setup..."
log_and_time "terraform apply -parallelism=10 -auto-approve tfplan"

# Fetch the public IP output from Terraform
PUBLIC_IP=$(terraform output -raw public_ip)
echo "VM Public IP: $PUBLIC_IP"

# Wait for the VM to be in 'running' state
echo "Waiting for VM to be in 'running' state..."
while [ "$(az vm get-instance-view --name myVM --resource-group $RESOURCE_GROUP_NAME --query "instanceView.statuses[?code=='PowerState/running'] | [0].code" --output tsv)" != "PowerState/running" ]; do
    echo "Waiting for VM to be running..."
    sleep 10
done

# Wait for the SSH port to be available
echo "Waiting for the SSH port to be available..."
while ! nc -z $PUBLIC_IP 22; do
    echo "Waiting for SSH to be available..."
    sleep 10
done

# Connect to the VM and set up Docker, Docker Compose, and other dependencies
ssh -o StrictHostKeyChecking=no -i id_rsa azureuser@$PUBLIC_IP << EOF
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get install -y docker-ce

# Add user to the Docker group
sudo usermod -aG docker $(whoami)

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Install VS Code Server
curl -fsSL https://code-server.dev/install.sh | sh
sudo mkdir -p /etc/systemd/system/code-server@.service.d/
echo -e '[Service]\nEnvironment="PASSWORD=$VS_CODE_PASSWORD"\nExecStart=\nExecStart=/usr/bin/code-server --bind-addr 0.0.0.0:8000' | sudo tee /etc/systemd/system/code-server@.service.d/override.conf
sudo systemctl daemon-reload
sudo systemctl enable --now code-server@$(whoami)

# Install GitHub CLI
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt-get update
sudo apt-get install -y gh

# Create project directory if it does not exist
mkdir -p /home/azureuser/projects/capstone-project-nelo-mlb-stats

EOF

# Copy the project files to the VM
log_and_time "rsync -avz --exclude 'terraform-azure-vm-setup' ./ azureuser@$PUBLIC_IP:/home/azureuser/projects/capstone-project-nelo-mlb-stats"

# Start services with Docker Compose on the VM
ssh -o StrictHostKeyChecking=no -i id_rsa azureuser@$PUBLIC_IP << EOF
cd /home/azureuser/projects/capstone-project-nelo-mlb-stats
docker-compose up -d
EOF

echo "Setup complete. You can now access your VM at $PUBLIC_IP"

# Apply Terraform plan for PostgreSQL databases
echo "Creating Terraform plan for PostgreSQL databases..."
log_and_time "terraform plan -out=tfplan-postgres -var=\"admin_username=$AZURE_POSTGRES_USERNAME\" -var=\"admin_password=$AZURE_POSTGRES_PASSWORD\" -var=\"airflow_db=airflow\" -var=\"superset_db=superset\" -var=\"hive_db=hive\" -var=\"mlflow_db=mlflow\" -var=\"haystack_db=haystack\" -var=\"zookeeper_db=zookeeper\" -var=\"kafka_db=kafka\" -var=\"pgadmin_db=pgadmin\" -var=\"trino_db=trino\" -var=\"qdrant_db=qdrant\" -var=\"spark_db=spark\""

echo "Applying Terraform plan for PostgreSQL databases..."
log_and_time "terraform apply -auto-approve tfplan-postgres"

#!/bin/bash

## Instructions to obtain Azure credentials:

# 1. Azure Subscription ID:
#    - Navigate to the Azure portal (https://portal.azure.com).
#    - In the left sidebar, click on "Subscriptions".
#    - Select the subscription you want to use.
#    - The Subscription ID will be displayed at the top of the subscription overview page.

# 2. Tenant ID:
#    - In the Azure portal, go to "Azure Active Directory".
#    - In the overview section, you will find the Tenant ID.

# 3. Client ID and Client Secret (Service Principal):
#    - Go to "Azure Active Directory" in the Azure portal.
#    - In the left sidebar, click on "App registrations".
#    - Click on "New registration".
#        - Name: Give your application a name.
#        - Supported account types: Select "Accounts in this organizational directory only".
#        - Redirect URI: You can leave this blank for now.
#    - Click "Register".
#    - Once registered, you will be redirected to the application's overview page where you will see the Application (client) ID. This is your ARM_CLIENT_ID.
#    - Next, click on "Certificates & secrets" in the left sidebar.
#    - Under "Client secrets", click "New client secret".
#    - Add a description and select the expiry period, then click "Add".
#    - The new client secret will be displayed. Copy the Value immediately; this is your ARM_CLIENT_SECRET. You won't be able to see it again once you navigate away.

# 4. Admin Username and Password:
#    - These are the credentials you want to set for the admin user on your Azure VM. You can choose any username and password you prefer. Make sure to store them securely.

# save these variables in .env file

#    - ARM_CLIENT_ID
#    - ARM_CLIENT_SECRET
#    - ARM_SUBSCRIPTION_ID
#    - ARM_TENANT_ID
#    - ADMIN_USERNAME
#    - ADMIN_PASSWORD

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

# Ensure RESOURCE_GROUP_NAME is set
if [ -z "$RESOURCE_GROUP_NAME" ]; then
    echo "RESOURCE_GROUP_NAME is not set. Please set it in the .env file."
    exit 1
fi

# Ensure STORAGE_ACCOUNT_NAME is set
if [ -z "$STORAGE_ACCOUNT_NAME" ]; then
    echo "STORAGE_ACCOUNT_NAME is not set. Please set it in the .env file."
    exit 1
fi

# Ensure required environment variables are set
required_vars=(RESOURCE_GROUP_NAME STORAGE_ACCOUNT_NAME ARM_CLIENT_ID ARM_CLIENT_SECRET ARM_TENANT_ID ARM_SUBSCRIPTION_ID)
for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    echo "$var is not set. Please set it in the .env file."
    exit 1
  fi
done

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

# Store the PostgreSQL credentials in Vault
log_and_time "vault kv put secret/data/postgres username='$AZURE_POSTGRES_USERNAME' password='$AZURE_POSTGRES_PASSWORD'"

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

# Check if the resource group exists
if az group show --name "$RESOURCE_GROUP_NAME" > /dev/null 2>&1; then
    echo "Resource group $RESOURCE_GROUP_NAME already exists."
else
    echo "Creating resource group $RESOURCE_GROUP_NAME..."
    az group create --name "$RESOURCE_GROUP_NAME" --location "East US"
fi

# Navigate to the project directory
cd "$PROJECT_DIR"

# Generate SSH key pair if not exists
if [ ! -f id_rsa ] || [ ! -f id_rsa.pub ]; then
    echo "Generating SSH key pair..."
    ssh-keygen -t rsa -b 4096 -f id_rsa -q -N ""
fi

# Export SSH public key for Terraform
export TF_VAR_ssh_public_key=$(cat id_rsa.pub)

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
    else
        echo "$resource_type $resource_id does not exist. Creating new resource..."
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

# Import existing resources if they exist
log_and_time "import_resource azurerm_resource_group.main $RESOURCE_GROUP_ID"
log_and_time "import_resource azurerm_storage_account.storage $STORAGE_ACCOUNT_ID"
log_and_time "import_resource azurerm_virtual_network.vnet $VNET_ID"
log_and_time "import_resource azurerm_subnet.subnet $SUBNET_ID"
log_and_time "import_resource azurerm_network_security_group.nsg $NSG_ID"
log_and_time "import_resource azurerm_network_interface.nic $NIC_ID"
log_and_time "import_resource azurerm_virtual_machine.vm $VM_ID"
log_and_time "import_resource azurerm_managed_disk.my_disk $DISK_ID"
log_and_time "import_resource azurerm_postgresql_server.postgres_server $POSTGRES_SERVER_ID"
log_and_time "import_resource azurerm_storage_container.container $CONTAINER_ID"


# Import existing PostgreSQL databases
log_and_time "import_resource azurerm_postgresql_database.airflow_db /subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/$POSTGRES_SERVER_NAME/databases/$AZURE_AIRFLOW_DB"
log_and_time "import_resource azurerm_postgresql_database.superset_db /subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/$POSTGRES_SERVER_NAME/databases/$AZURE_SUPERSET_DB"
log_and_time "import_resource azurerm_postgresql_database.hive_db /subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/$POSTGRES_SERVER_NAME/databases/$AZURE_HIVE_DB"
log_and_time "import_resource azurerm_postgresql_database.mlflow_db /subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/$POSTGRES_SERVER_NAME/databases/$AZURE_MLFLOW_DB"
log_and_time "import_resource azurerm_postgresql_database.haystack_db /subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/$POSTGRES_SERVER_NAME/databases/$AZURE_HAYSTACK_DB"
log_and_time "import_resource azurerm_postgresql_database.zookeeper_db /subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/$POSTGRES_SERVER_NAME/databases/$AZURE_ZOOKEEPER_DB"
log_and_time "import_resource azurerm_postgresql_database.kafka_db /subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/$POSTGRES_SERVER_NAME/databases/$AZURE_KAFKA_DB"
log_and_time "import_resource azurerm_postgresql_database.pgadmin_db /subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/$POSTGRES_SERVER_NAME/databases/$AZURE_PGADMIN_DB"
log_and_time "import_resource azurerm_postgresql_database.trino_db /subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/$POSTGRES_SERVER_NAME/databases/$AZURE_TRINO_DB"
log_and_time "import_resource azurerm_postgresql_database.qdrant_db /subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/$POSTGRES_SERVER_NAME/databases/$AZURE_QDRANT_DB"
log_and_time "import_resource azurerm_postgresql_database.spark_db /subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DBforPostgreSQL/servers/$POSTGRES_SERVER_NAME/databases/$AZURE_SPARK_DB"

# Apply Terraform plan for VM setup
echo "Creating Terraform plan for VM setup..."
log_and_time "terraform plan -parallelism=10 -out=tfplan"

echo "Applying Terraform plan for VM setup..."
log_and_time "terraform apply -parallelism=10 -auto-approve tfplan"

# Extract the storage account key from Terraform output
STORAGE_ACCOUNT_KEY=$(terraform output -json storage_account_key | jq -r '.value')

# Check if the .env file exists
if [ ! -f ../.env ]; then
  touch ../.env
fi

# Update the .env file with the storage account key
if grep -q "AZURE_ACCOUNT_KEY" ../.env; then
  sed -i "s|^AZURE_ACCOUNT_KEY=.*|AZURE_ACCOUNT_KEY=${STORAGE_ACCOUNT_KEY}|" ../.env
else
  echo "AZURE_ACCOUNT_KEY=${STORAGE_ACCOUNT_KEY}" >> ../.env
fi

echo "Updated .env file with storage account key."

# Fetch the public IP output from Terraform
PUBLIC_IP=$(terraform output -raw public_ip)
echo "VM Public IP: $PUBLIC_IP"

# Wait for the VM to be in 'running' state
echo "Waiting for VM to be in 'running' state..."
while [ "$(az vm get-instance-view --name $VIRTUAL_MACHINE_NAME --resource-group $RESOURCE_GROUP_NAME --query "instanceView.statuses[?code=='PowerState/running'] | [0].code" --output tsv)" != "PowerState/running" ]; do
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
log_and_time "terraform plan -out=tfplan-postgres -var="admin_username=$AZURE_POSTGRES_USERNAME" -var="admin_password=$AZURE_POSTGRES_PASSWORD" -var="airflow_db=$AZURE_AIRFLOW_DB" -var="superset_db=$AZURE_SUPERSET_DB" -var="hive_db=$AZURE_HIVE_DB" -var="mlflow_db=$AZURE_MLFLOW_DB" -var="haystack_db=$AZURE_HAYSTACK_DB" -var="zookeeper_db=$AZURE_ZOOKEEPER_DB" -var="kafka_db=$AZURE_KAFKA_DB" -var="pgadmin_db=$AZURE_PGADMIN_DB" -var="trino_db=$AZURE_TRINO_DB" -var="qdrant_db=$AZURE_QDRANT_DB" -var="spark_db=$AZURE_SPARK_DB""

echo "Applying Terraform plan for PostgreSQL databases..."
log_and_time "terraform apply -auto-approve tfplan-postgres"

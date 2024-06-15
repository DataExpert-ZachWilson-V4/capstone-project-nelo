#!/bin/bash

# Self-setting execute permissions
if [ ! -x "$0" ]; then
  chmod +x "$0"
fi

# Exit immediately if a command exits with a non-zero status.
set -e

# Directory containing your project
PROJECT_DIR="$(dirname "$0")"

# Install Terraform if not installed
if ! [ -x "$(command -v terraform)" ]; then
  echo "Terraform is not installed. Installing Terraform..."
  sudo apt-get update
  sudo apt-get install -y gnupg software-properties-common curl
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt-get update
  sudo apt-get install -y terraform
fi

# Install Azure CLI if not installed
if ! [ -x "$(command -v az)" ]; then
  echo "Azure CLI is not installed. Installing Azure CLI..."
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl apt-transport-https lsb-release gnupg
  curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/microsoft-archive-keyring.gpg > /dev/null
  AZ_REPO=$(lsb_release -cs)
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | sudo tee /etc/apt/sources.list.d/azure-cli.list
  sudo apt-get update
  sudo apt-get install -y azure-cli
fi

# Install sshpass if not installed
if ! [ -x "$(command -v sshpass)" ]; then
  echo "sshpass is not installed. Installing sshpass..."
  sudo apt-get update
  sudo apt-get install -y sshpass
fi

# Verify installations
terraform -v
az --version
sshpass -V

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
if [ $(az account list --query "[?id=='$ARM_SUBSCRIPTION_ID'] | length(@)") -eq 0 ]; then
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

# Instructions for assigning Owner role to the service principal:
# This action requires either the Owner role or a custom role with Microsoft.Authorization/roleAssignments/write permissions on the subscription.
# Here’s a step-by-step guide to fix this:
# Step 1: Assign the Required Permissions to the Service Principal
# To perform role assignments, the service principal must have the necessary permissions. Usually, this means assigning the Owner role to the service principal.
# 1. Log in to the Azure Portal: Open the Azure Portal.
# 2. Navigate to Subscriptions: Go to the Subscriptions section and select the subscription where you want to assign the role.
# 3. Access Control (IAM): Click on Access Control (IAM) on the left-hand menu.
# 4. Add Role Assignment:
#    - Click Add and then Add role assignment.
#    - Select Owner as the role.
#    - Choose Azure AD user, group, or service principal as the Assign access to.
#    - Search for your service principal by name or application ID (3d434808-9e7c-42b0-9a77-0baa67b161a5).
#    - Select the service principal and click Save.

# Go to the project directory
cd "$PROJECT_DIR"

# Apply Terraform changes and get the public IP
echo "Applying Terraform changes..."
cd terraform-azure-vm-setup
terraform init
terraform apply -auto-approve

# Fetch the public IP output from Terraform
PUBLIC_IP=$(terraform output -raw public_ip)
echo "VM Public IP: $PUBLIC_IP"

# Wait for the VM to be ready to accept SSH connections
echo "Waiting for the VM to be ready to accept SSH connections..."
sleep 60

# Connect to the VM and set up Docker, Docker Compose, and other dependencies
sshpass -p "$ADMIN_PASSWORD" ssh -o StrictHostKeyChecking=no azureuser@$PUBLIC_IP << 'EOF'
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get install -y docker-ce

# Add user to the Docker group
sudo usermod -aG docker \$(whoami)

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-\$(uname -s)-\$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Install VS Code Server
curl -fsSL https://code-server.dev/install.sh | sh
sudo mkdir -p /etc/systemd/system/code-server@.service.d/
echo -e '[Service]\nEnvironment="PASSWORD=yourpassword"\nExecStart=\nExecStart=/usr/bin/code-server --bind-addr 0.0.0.0:8000' | sudo tee /etc/systemd/system/code-server@.service.d/override.conf
sudo systemctl daemon-reload
sudo systemctl enable --now code-server@\$(whoami)

# Install GitHub CLI
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt-get update
sudo apt-get install -y gh

# Create project directory if it does not exist
mkdir -p /home/azureuser/projects/capstone-project-nelo-mlb-stats

EOF

# Copy the project files to the VM
rsync -avz --exclude 'terraform-azure-vm-setup' ./ azureuser@$PUBLIC_IP:/home/azureuser/projects/capstone-project-nelo-mlb-stats

# Start services with Docker Compose on the VM
sshpass -p "$ADMIN_PASSWORD" ssh -o StrictHostKeyChecking=no azureuser@$PUBLIC_IP << 'EOF'
cd /home/azureuser/projects/capstone-project-nelo-mlb-stats
docker-compose up -d
EOF

echo "Setup complete. You can now access your VM at $PUBLIC_IP"

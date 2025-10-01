#!/bin/bash

# Azure Resource Inventory Web Interface Deployment Script
# This script builds and deploys the ARI web interface to Azure Container Instances

set -e

# Configuration
RESOURCE_GROUP_NAME="rg-ari-web-interface"
LOCATION="eastus"
ACR_NAME="acrariwebinterface$(date +%s)"
CONTAINER_GROUP_NAME="ari-web-interface"
IMAGE_NAME="ari-web-interface"
IMAGE_TAG="latest"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    print_error "You are not logged in to Azure. Please run 'az login' first."
    exit 1
fi

print_status "Starting deployment of Azure Resource Inventory Web Interface..."

# Create resource group
print_status "Creating resource group: $RESOURCE_GROUP_NAME"
az group create \
    --name "$RESOURCE_GROUP_NAME" \
    --location "$LOCATION" \
    --output table

# Create Azure Container Registry
print_status "Creating Azure Container Registry: $ACR_NAME"
az acr create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$ACR_NAME" \
    --sku Basic \
    --admin-enabled true \
    --output table

# Get ACR login server
ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query loginServer --output tsv)
print_success "ACR Login Server: $ACR_LOGIN_SERVER"

# Build and push Docker image
print_status "Building Docker image..."
cd "$(dirname "$0")/.."

# Build the image
docker build -t "$IMAGE_NAME:$IMAGE_TAG" .

# Tag the image for ACR
docker tag "$IMAGE_NAME:$IMAGE_TAG" "$ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG"

# Login to ACR
print_status "Logging in to Azure Container Registry..."
az acr login --name "$ACR_NAME"

# Push the image
print_status "Pushing image to Azure Container Registry..."
docker push "$ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG"

print_success "Image pushed successfully: $ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG"

# Get ACR credentials
ACR_USERNAME=$(az acr credential show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query username --output tsv)
ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query passwords[0].value --output tsv)

# Deploy to Azure Container Instances
print_status "Deploying to Azure Container Instances..."
az deployment group create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --template-file "azure-deployment/deploy-aci.json" \
    --parameters \
        containerGroupName="$CONTAINER_GROUP_NAME" \
        containerImageName="$ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG" \
        registryUsername="$ACR_USERNAME" \
        registryPassword="$ACR_PASSWORD" \
        cpuCores="2" \
        memoryInGb="4" \
    --output table

# Get the application URL
APPLICATION_URL=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "deploy-aci" \
    --query properties.outputs.applicationUrl.value \
    --output tsv)

print_success "Deployment completed successfully!"
print_success "Application URL: $APPLICATION_URL"

# Display connection information
print_status "Deployment Summary:"
echo "=================================="
echo "Resource Group: $RESOURCE_GROUP_NAME"
echo "Container Registry: $ACR_NAME"
echo "Container Group: $CONTAINER_GROUP_NAME"
echo "Image: $ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG"
echo "Application URL: $APPLICATION_URL"
echo "=================================="

print_warning "Note: It may take a few minutes for the container to start and be accessible."
print_status "You can monitor the deployment status with:"
echo "az container show --resource-group $RESOURCE_GROUP_NAME --name $CONTAINER_GROUP_NAME --output table"

print_status "To view container logs:"
echo "az container logs --resource-group $RESOURCE_GROUP_NAME --name $CONTAINER_GROUP_NAME"

print_status "To clean up resources when done:"
echo "az group delete --name $RESOURCE_GROUP_NAME --yes --no-wait"
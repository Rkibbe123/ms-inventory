#!/usr/bin/env bash
set -euo pipefail

# This script builds the container image, pushes it to Azure Container Registry,
# and deploys it to Azure Container Apps. Non-interactive; requires AZ login beforehand.

if [[ $# -lt 5 ]]; then
  echo "Usage: $0 <subscription-id> <resource-group> <location> <acr-name> <app-name> [env-name]"
  exit 1
fi

SUBSCRIPTION_ID="$1"
RESOURCE_GROUP="$2"
LOCATION="$3"
ACR_NAME="$4"
APP_NAME="$5"
ENV_NAME="${6:-${APP_NAME}-env}"

IMAGE_TAG="${ACR_NAME}.azurecr.io/ari-runner:latest"

echo "Setting subscription..."
az account set --subscription "$SUBSCRIPTION_ID"

echo "Ensuring resource group..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none

echo "Ensuring ACR..."
az acr show --name "$ACR_NAME" >/dev/null 2>&1 || \
  az acr create --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --sku Basic --location "$LOCATION" --output none

echo "Logging into ACR..."
az acr login --name "$ACR_NAME"

echo "Building image..."
az acr build --registry "$ACR_NAME" --image "${IMAGE_TAG#${ACR_NAME}.azurecr.io/}" .

echo "Ensuring Container Apps env..."
az extension add --name containerapp --upgrade --yes >/dev/null 2>&1 || true
az provider register --namespace Microsoft.App --wait

az containerapp env show \
  --name "$ENV_NAME" \
  --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1 || \
az containerapp env create \
  --name "$ENV_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" --output none

echo "Creating or updating Container App..."
if az containerapp show --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
  az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --image "$IMAGE_TAG" \
    --set-env-vars "PORT=8000" "ARI_OUTPUT_DIR=/data/AzureResourceInventory" \
    --ingress external --target-port 8000 --transport http
else
  az containerapp create \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --environment "$ENV_NAME" \
    --image "$IMAGE_TAG" \
    --ingress external --target-port 8000 --transport http \
    --set-env-vars "PORT=8000" "ARI_OUTPUT_DIR=/data/AzureResourceInventory"
fi

echo "Deployment complete. URL:"
az containerapp show --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" --query properties.configuration.ingress.fqdn -o tsv


# Quick Deploy Script for Azure Resource Inventory
# Builds and deploys the updated container to Azure Container Apps

Write-Host "🚀 Starting Quick Deployment..." -ForegroundColor Green
Write-Host ""

# Configuration
$IMAGE_NAME = "rkazureinventory.azurecr.io/azure-resource-inventory:v6.27"
$CONTAINER_APP = "ms-inventory"
$RESOURCE_GROUP = "rg-rkibbe-2470"

# Step 1: Build Docker image
Write-Host "📦 Step 1: Building Docker image..." -ForegroundColor Cyan
docker build -t $IMAGE_NAME .
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Docker build failed!" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Docker build completed" -ForegroundColor Green
Write-Host ""

# Step 2: Push to Azure Container Registry
Write-Host "📤 Step 2: Pushing to Azure Container Registry..." -ForegroundColor Cyan
docker push $IMAGE_NAME
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Docker push failed!" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Docker push completed" -ForegroundColor Green
Write-Host ""

# Step 3: Update Azure Container App
Write-Host "🔄 Step 3: Updating Azure Container App..." -ForegroundColor Cyan
az containerapp update `
    --name $CONTAINER_APP `
    --resource-group $RESOURCE_GROUP `
    --image $IMAGE_NAME
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Container App update failed!" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Container App updated successfully!" -ForegroundColor Green
Write-Host ""

# Step 4: Get the URL
Write-Host "🌐 Step 4: Getting application URL..." -ForegroundColor Cyan
$url = az containerapp show `
    --name $CONTAINER_APP `
    --resource-group $RESOURCE_GROUP `
    --query "properties.configuration.ingress.fqdn" `
    --output tsv

if ($url) {
    Write-Host "✅ Deployment completed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "🌍 Application URL: https://$url" -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host "⚠️  Deployment completed but couldn't retrieve URL" -ForegroundColor Yellow
}

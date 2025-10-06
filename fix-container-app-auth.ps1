#!/usr/bin/env pwsh
# Fix Azure Container App Authentication Issues
# This script configures managed identity for your container app

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "rg-rkibbe-2470",
    
    [Parameter(Mandatory=$false)]
    [string]$ContainerAppName = "azure-resource-inventory",
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = "d5736eb1-f851-4ec3-a2c5-ac8d84d029e2"
)

Write-Host "🔧 Fixing Azure Container App Authentication" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# Check if Azure CLI is available
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Azure CLI not found. Please install Azure CLI first." -ForegroundColor Red
    exit 1
}

# Login check
$currentAccount = az account show --output json 2>$null | ConvertFrom-Json
if (-not $currentAccount) {
    Write-Host "🔑 Please login to Azure CLI first:" -ForegroundColor Yellow
    Write-Host "   az login" -ForegroundColor White
    exit 1
}

Write-Host "✅ Connected to Azure as: $($currentAccount.user.name)" -ForegroundColor Green
Write-Host "📋 Subscription: $($currentAccount.name)" -ForegroundColor Cyan

# Set subscription
az account set --subscription $SubscriptionId

Write-Host ""
Write-Host "🔧 Step 1: Enable System-Assigned Managed Identity" -ForegroundColor Yellow

# Enable managed identity on the container app
$identityResult = az containerapp identity assign `
    --name $ContainerAppName `
    --resource-group $ResourceGroupName `
    --system-assigned `
    --output json

if ($LASTEXITCODE -eq 0) {
    $identity = $identityResult | ConvertFrom-Json
    $principalId = $identity.principalId
    Write-Host "✅ Managed identity enabled" -ForegroundColor Green
    Write-Host "🔑 Principal ID: $principalId" -ForegroundColor Cyan
} else {
    Write-Host "❌ Failed to enable managed identity" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "🔧 Step 2: Assign Reader Role at Subscription Level" -ForegroundColor Yellow

# Assign Reader role to the managed identity
az role assignment create `
    --assignee $principalId `
    --role "Reader" `
    --scope "/subscriptions/$SubscriptionId"

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Reader role assigned successfully" -ForegroundColor Green
} else {
    Write-Host "⚠️ Role assignment may have failed, but continuing..." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "🔧 Step 3: Update Container App Environment Variables" -ForegroundColor Yellow

# Update container app to use managed identity
az containerapp update `
    --name $ContainerAppName `
    --resource-group $ResourceGroupName `
    --set-env-vars "AZURE_CLIENT_ID=MSI" "USE_MANAGED_IDENTITY=true"

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Environment variables updated" -ForegroundColor Green
} else {
    Write-Host "⚠️ Environment variable update may have failed" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "🎉 SETUP COMPLETE!" -ForegroundColor Green
Write-Host "==================" -ForegroundColor Green
Write-Host "Your Azure Container App now has:" -ForegroundColor White
Write-Host "  ✓ System-assigned managed identity" -ForegroundColor Green
Write-Host "  ✓ Reader access to subscription $SubscriptionId" -ForegroundColor Green
Write-Host "  ✓ Automatic authentication (no device login needed)" -ForegroundColor Green
Write-Host ""
Write-Host "🌐 Try accessing your app again - it should work without authentication errors!" -ForegroundColor Cyan
Write-Host ""
Write-Host "💡 If you still see issues, restart the container app:" -ForegroundColor Yellow
Write-Host "   az containerapp revision restart --name $ContainerAppName --resource-group $ResourceGroupName" -ForegroundColor White
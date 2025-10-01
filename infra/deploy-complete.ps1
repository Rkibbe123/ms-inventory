# PowerShell script to deploy Container Apps Environment and Application
# This script creates everything needed for the Azure Resource Inventory app

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "rg-rkibbe-2470",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus",
    
    [Parameter(Mandatory=$false)]
    [string]$EnvironmentName = "ari-inventory-env",
    
    [Parameter(Mandatory=$false)]
    [string]$ContainerAppName = "azure-resource-inventory",
    
    [Parameter(Mandatory=$false)]
    [string]$AcrName = "rkazureinventory"
)

Write-Host "🚀 Starting Container Apps deployment..." -ForegroundColor Cyan

# Check if user is logged in
try {
    $context = az account show 2>$null
    if (-not $context) {
        Write-Host "❌ Please login to Azure first: az login" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Azure CLI authenticated" -ForegroundColor Green
}
catch {
    Write-Host "❌ Please install Azure CLI and login: az login" -ForegroundColor Red
    exit 1
}

# Deploy using Bicep template
Write-Host "📦 Deploying with Bicep template..." -ForegroundColor Yellow

$deploymentName = "ari-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

try {
    $deployment = az deployment group create `
        --resource-group $ResourceGroupName `
        --template-file "infra/complete-deployment.bicep" `
        --parameters environmentName=$EnvironmentName containerAppName=$ContainerAppName acrName=$AcrName location=$Location `
        --name $deploymentName `
        --output json | ConvertFrom-Json
    
    Write-Host "✅ Deployment completed successfully!" -ForegroundColor Green
    
    # Get the application URL
    $appUrl = $deployment.properties.outputs.applicationUrl.value
    $envName = $deployment.properties.outputs.environmentName.value
    $appName = $deployment.properties.outputs.containerAppName.value
    
    Write-Host "🌐 Application Details:" -ForegroundColor Cyan
    Write-Host "   Environment: $envName" -ForegroundColor White
    Write-Host "   Container App: $appName" -ForegroundColor White
    Write-Host "   URL: $appUrl" -ForegroundColor Green
    Write-Host ""
    Write-Host "🎉 Your Azure Resource Inventory app is now running!" -ForegroundColor Green
    Write-Host "   You can access it at: $appUrl" -ForegroundColor Cyan
}
catch {
    Write-Host "❌ Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "💡 You can also deploy manually through the Azure Portal" -ForegroundColor Yellow
}

# Alternative: Manual steps if Bicep fails
Write-Host ""
Write-Host "📋 Manual deployment steps (if Bicep deployment fails):" -ForegroundColor Yellow
Write-Host "1. Go to Azure Portal -> Container Apps Environments" -ForegroundColor White
Write-Host "2. Click '+ Create'" -ForegroundColor White
Write-Host "3. Use Resource Group: $ResourceGroupName" -ForegroundColor White
Write-Host "4. Environment name: $EnvironmentName" -ForegroundColor White
Write-Host "5. Region: $Location" -ForegroundColor White
Write-Host "6. Create the environment, then create a Container App in it" -ForegroundColor White
Write-Host "7. Use image: $AcrName.azurecr.io/azure-resource-inventory:latest" -ForegroundColor White
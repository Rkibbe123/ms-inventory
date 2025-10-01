# PowerShell script to configure managed identity and permissions
# This script sets up secure authentication for the Azure Resource Inventory app

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "rg-rkibbe-2470",
    
    [Parameter(Mandatory=$false)]
    [string]$ContainerAppName = "azure-resource-inventory",
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = "d5736eb1-f851-4ec3-a2c5-ac8d84d029e2"
)

Write-Host "🔐 Configuring managed identity for Azure Resource Inventory..." -ForegroundColor Cyan

# Check if PowerShell Az module is installed
if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Write-Host "📦 Installing Azure PowerShell module..." -ForegroundColor Yellow
    Install-Module -Name Az.Accounts, Az.Resources, Az.ContainerApps -Force -AllowClobber
}

# Connect to Azure
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "🔑 Please login to Azure..." -ForegroundColor Yellow
        Connect-AzAccount
    }
    Write-Host "✅ Connected to Azure" -ForegroundColor Green
}
catch {
    Write-Host "❌ Failed to connect to Azure: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Set subscription context
Set-AzContext -SubscriptionId $SubscriptionId

try {
    # Enable system-assigned managed identity using REST API
    $resourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.App/containerApps/$ContainerAppName"
    
    Write-Host "🔧 Enabling managed identity..." -ForegroundColor Yellow
    
    # Get current container app configuration
    $containerApp = Invoke-AzRestMethod -Uri "https://management.azure.com$resourceId?api-version=2023-05-01" -Method GET
    
    if ($containerApp.StatusCode -eq 200) {
        $appConfig = $containerApp.Content | ConvertFrom-Json
        
        # Add managed identity
        if (-not $appConfig.identity) {
            $appConfig.identity = @{ type = "SystemAssigned" }
        }
        else {
            $appConfig.identity.type = "SystemAssigned"
        }
        
        # Update the container app
        $updateBody = $appConfig | ConvertTo-Json -Depth 20
        $updateResult = Invoke-AzRestMethod -Uri "https://management.azure.com$resourceId?api-version=2023-05-01" -Method PUT -Payload $updateBody
        
        if ($updateResult.StatusCode -eq 200) {
            Write-Host "✅ Managed identity enabled successfully" -ForegroundColor Green
            
            # Get the principal ID
            $updatedApp = $updateResult.Content | ConvertFrom-Json
            $principalId = $updatedApp.identity.principalId
            
            Write-Host "🔑 Principal ID: $principalId" -ForegroundColor Cyan
            
            # Assign Reader role at subscription level
            Write-Host "🔐 Assigning Reader role..." -ForegroundColor Yellow
            $readerRoleId = "acdd72a7-3385-48ef-bd42-f606fba81ae7"  # Reader role
            $roleAssignmentId = [System.Guid]::NewGuid()
            
            $roleBody = @{
                properties = @{
                    roleDefinitionId = "/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/roleDefinitions/$readerRoleId"
                    principalId = $principalId
                    principalType = "ServicePrincipal"
                }
            } | ConvertTo-Json
            
            $roleUri = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/roleAssignments/$roleAssignmentId" + "?api-version=2022-04-01"
            $roleResult = Invoke-AzRestMethod -Uri $roleUri -Method PUT -Payload $roleBody
            
            if ($roleResult.StatusCode -eq 201 -or $roleResult.StatusCode -eq 200) {
                Write-Host "✅ Reader role assigned successfully" -ForegroundColor Green
                Write-Host ""
                Write-Host "🎉 Setup complete! Your Azure Resource Inventory app now has:" -ForegroundColor Green
                Write-Host "   ✓ System-assigned managed identity" -ForegroundColor White
                Write-Host "   ✓ Reader access to the subscription" -ForegroundColor White
                Write-Host "   ✓ Can authenticate automatically without device login" -ForegroundColor White
                Write-Host ""
                Write-Host "🌐 Access your app at: https://azure-resource-inventory.ambitiousbeach-c62b6a92.eastus.azurecontainerapps.io" -ForegroundColor Cyan
            }
            else {
                Write-Host "⚠️ Role assignment may have failed. You can assign it manually in the Azure Portal" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "❌ Failed to enable managed identity" -ForegroundColor Red
        }
    }
    else {
        Write-Host "❌ Container app not found or access denied" -ForegroundColor Red
    }
}
catch {
    Write-Host "❌ Error configuring managed identity: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "💡 Alternative: Use Device Login in the web interface" -ForegroundColor Yellow
}
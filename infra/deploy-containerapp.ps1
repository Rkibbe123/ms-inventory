# PowerShell script to deploy to Container Apps using REST API
# Run this script if Azure CLI connectivity issues persist

# Set variables
$subscriptionId = "d5736eb1-f851-4ec3-a2c5-ac8d84d029e2"  # Replace with your subscription ID
$resourceGroupName = "rg-rkibbe-2470"
$containerAppName = "azure-resource-inventory"
$environmentName = "rk-azure-inventory"
$acrName = "rkazureinventory"
$imageName = "azure-resource-inventory:latest"
$location = "eastus"

# Get access token
$context = Get-AzContext
if (-not $context) {
    Write-Host "Please run Connect-AzAccount first" -ForegroundColor Red
    exit 1
}

$token = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($context.Account, $context.Environment, $context.Tenant.Id, $null, "Never", $null, "https://management.azure.com/").AccessToken

# Get ACR credentials
$acrCredentials = az acr credential show --name $acrName --query "{username:username, password:passwords[0].value}" --output json | ConvertFrom-Json

# Container App JSON payload
$containerAppPayload = @{
    location = $location
    properties = @{
        managedEnvironmentId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.App/managedEnvironments/$environmentName"
        configuration = @{
            registries = @(
                @{
                    server = "$acrName.azurecr.io"
                    username = $acrCredentials.username
                    passwordSecretRef = "acr-password"
                }
            )
            secrets = @(
                @{
                    name = "acr-password"
                    value = $acrCredentials.password
                }
            )
            ingress = @{
                external = $true
                targetPort = 8000
                allowInsecure = $false
                traffic = @(
                    @{
                        latestRevision = $true
                        weight = 100
                    }
                )
            }
        }
        template = @{
            containers = @(
                @{
                    name = $containerAppName
                    image = "$acrName.azurecr.io/$imageName"
                    resources = @{
                        cpu = 1.0
                        memory = "2.0Gi"
                    }
                    env = @(
                        @{
                            name = "PORT"
                            value = "8000"
                        }
                        @{
                            name = "PYTHONUNBUFFERED"
                            value = "1"
                        }
                        @{
                            name = "ARI_OUTPUT_DIR"
                            value = "/data/AzureResourceInventory"
                        }
                    )
                }
            )
            scale = @{
                minReplicas = 1
                maxReplicas = 3
            }
        }
    }
} | ConvertTo-Json -Depth 10

# API endpoint
$uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.App/containerApps/$containerAppName" + "?api-version=2023-05-01"

# Headers
$headers = @{
    'Authorization' = "Bearer $token"
    'Content-Type' = 'application/json'
}

try {
    # Create the Container App
    Write-Host "Creating Container App: $containerAppName..." -ForegroundColor Yellow
    $response = Invoke-RestMethod -Uri $uri -Method PUT -Body $containerAppPayload -Headers $headers
    
    Write-Host "Container App created successfully!" -ForegroundColor Green
    Write-Host "Application URL: https://$($response.properties.configuration.ingress.fqdn)" -ForegroundColor Cyan
}
catch {
    Write-Host "Error creating Container App: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Response: $($_.Exception.Response)" -ForegroundColor Red
}
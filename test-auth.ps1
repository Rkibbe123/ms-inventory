# PowerShell script to test authentication in the container
# This will help diagnose what authentication method is being used

Write-Host "=== AZURE AUTHENTICATION DIAGNOSTIC ==="
Write-Host "Testing current authentication state..."

# Check if we're running in Azure (managed identity)
$imdsEndpoint = "http://169.254.169.254/metadata/instance?api-version=2021-02-01"
try {
    $imdsResponse = Invoke-RestMethod -Uri $imdsEndpoint -Headers @{"Metadata" = "true"} -TimeoutSec 5 -ErrorAction Stop
    Write-Host "✅ RUNNING IN AZURE - Managed Identity Available" -ForegroundColor Green
    Write-Host "Compute Name: $($imdsResponse.compute.name)"
    Write-Host "Resource Group: $($imdsResponse.compute.resourceGroupName)"
} catch {
    Write-Host "❌ NOT running in Azure or no managed identity" -ForegroundColor Red
}

# Check Azure PowerShell context
Write-Host "`n=== AZURE POWERSHELL CONTEXT ==="
try {
    Import-Module Az.Accounts -Force
    $context = Get-AzContext
    if ($context) {
        Write-Host "✅ AZURE CONTEXT FOUND" -ForegroundColor Green
        Write-Host "Account: $($context.Account.Id)"
        Write-Host "Tenant: $($context.Tenant.Id)"
        Write-Host "Subscription: $($context.Subscription.Name)"
        Write-Host "Auth Type: $($context.Account.Type)"
    } else {
        Write-Host "❌ NO AZURE CONTEXT" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Error checking Azure context: $($_.Exception.Message)" -ForegroundColor Red
}

# Check environment variables
Write-Host "`n=== ENVIRONMENT VARIABLES ==="
$azureVars = @(
    'AZURE_CLIENT_ID', 
    'AZURE_CLIENT_SECRET', 
    'AZURE_TENANT_ID',
    'MSI_ENDPOINT',
    'IDENTITY_ENDPOINT',
    'IMDS_ENDPOINT'
)

foreach ($var in $azureVars) {
    $value = [Environment]::GetEnvironmentVariable($var)
    if ($value) {
        if ($var -like '*SECRET*') {
            Write-Host "$var = ***REDACTED***" -ForegroundColor Yellow
        } else {
            Write-Host "$var = $value" -ForegroundColor Yellow
        }
    } else {
        Write-Host "$var = (not set)" -ForegroundColor Gray
    }
}

Write-Host "`n=== FORCE DEVICE LOGIN TEST ==="
Write-Host "Clearing all contexts and forcing device login..."

try {
    # Clear all contexts
    Clear-AzContext -Force -ErrorAction SilentlyContinue
    Disconnect-AzAccount -ErrorAction SilentlyContinue
    
    Write-Host "All contexts cleared. Now attempting device login..."
    Write-Host "This should prompt for device authentication..."
    
    # Force device login
    Connect-AzAccount -DeviceCode -Force
    
    $newContext = Get-AzContext
    if ($newContext) {
        Write-Host "✅ DEVICE LOGIN SUCCESSFUL" -ForegroundColor Green
        Write-Host "New Account: $($newContext.Account.Id)"
        Write-Host "Auth Type: $($newContext.Account.Type)"
    }
} catch {
    Write-Host "❌ Device login failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== DIAGNOSTIC COMPLETE ==="
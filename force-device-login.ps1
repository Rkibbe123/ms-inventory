# FORCE DEVICE LOGIN SCRIPT
# This script ensures device login happens even with managed identity available

param(
    [string]$TenantID = "",
    [string]$SubscriptionID = "",
    [string]$ReportName = "AzureResourceInventory",
    [string]$ReportDir = "/data/AzureResourceInventory",
    [switch]$IncludeTags,
    [switch]$SkipAdvisory,
    [switch]$SkipDiagram
)

Write-Host "=== FORCING DEVICE LOGIN AUTHENTICATION ===" -ForegroundColor Cyan
Write-Host "This will clear all existing Azure contexts and force device login." -ForegroundColor Yellow

# Import required modules
Import-Module Az.Accounts -Force
Import-Module AzureResourceInventory -Force

# Step 1: Clear ALL Azure authentication
Write-Host "`n1. Clearing all Azure contexts..." -ForegroundColor Yellow
try {
    # Clear PowerShell contexts
    Get-AzContext -ListAvailable | ForEach-Object { Remove-AzContext -Name $_.Name -Force -ErrorAction SilentlyContinue }
    Clear-AzContext -Force -ErrorAction SilentlyContinue
    
    # Disconnect from Azure
    Disconnect-AzAccount -ErrorAction SilentlyContinue
    
    Write-Host "   ✓ All Azure contexts cleared" -ForegroundColor Green
} catch {
    Write-Host "   Warning: $($_.Exception.Message)" -ForegroundColor Orange
}

# Step 2: Remove environment variables that could bypass device login
Write-Host "`n2. Clearing authentication environment variables..." -ForegroundColor Yellow
$authVars = @('AZURE_CLIENT_ID', 'AZURE_CLIENT_SECRET', 'AZURE_TENANT_ID', 'MSI_ENDPOINT', 'IDENTITY_ENDPOINT')
foreach ($var in $authVars) {
    [Environment]::SetEnvironmentVariable($var, $null)
    Write-Host "   Cleared $var" -ForegroundColor Gray
}

# Step 3: Force device login
Write-Host "`n3. Initiating DEVICE LOGIN..." -ForegroundColor Yellow
Write-Host "   You should see device login instructions below:" -ForegroundColor Cyan
Write-Host "   - Look for 'To sign in, use a web browser...'" -ForegroundColor Cyan
Write-Host "   - Copy the device code" -ForegroundColor Cyan
Write-Host "   - Open the URL in your browser" -ForegroundColor Cyan
Write-Host "   - Enter the code when prompted" -ForegroundColor Cyan
Write-Host "" -ForegroundColor White

try {
    # Connect with device code - this WILL show the prompt
    if ($TenantID) {
        Connect-AzAccount -DeviceCode -Tenant $TenantID -Force
    } else {
        Connect-AzAccount -DeviceCode -Force
    }
    
    Write-Host "`n   ✓ Device login completed successfully!" -ForegroundColor Green
    
    # Verify authentication
    $context = Get-AzContext
    Write-Host "   Authenticated as: $($context.Account.Id)" -ForegroundColor Green
    Write-Host "   Tenant: $($context.Tenant.Id)" -ForegroundColor Green
    
} catch {
    Write-Host "`n   ❌ Device login failed: $($_.Exception.Message)" -ForegroundColor Red
    throw
}

# Step 4: Run Azure Resource Inventory
Write-Host "`n4. Running Azure Resource Inventory..." -ForegroundColor Yellow

# Prepare output directory
New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null

# Build ARI command
$ariParams = @{
    ReportDir = $ReportDir
    ReportName = $ReportName
}

if ($TenantID) { $ariParams.TenantID = $TenantID }
if ($SubscriptionID) { $ariParams.SubscriptionID = $SubscriptionID }
if ($IncludeTags) { $ariParams.IncludeTags = $true }
if ($SkipAdvisory) { $ariParams.SkipAdvisory = $true }
if ($SkipDiagram) { $ariParams.SkipDiagram = $true }

# Run ARI
try {
    Invoke-ARI @ariParams
    Write-Host "`n✅ Azure Resource Inventory completed successfully!" -ForegroundColor Green
} catch {
    Write-Host "`n❌ ARI execution failed: $($_.Exception.Message)" -ForegroundColor Red
    throw
}

Write-Host "`n=== PROCESS COMPLETE ===" -ForegroundColor Cyan
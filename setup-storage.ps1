# Add persistent storage to Azure Container App
# This will create an Azure Storage Account and mount it to /data for job persistence

$resourceGroup = "rg-rkibbe-2470"
$location = "eastus"
$storageAccountName = "ariinventorystorage$(Get-Random -Minimum 1000 -Maximum 9999)"
$fileShareName = "ari-data"
$containerAppName = "azure-resource-inventory"
$containerAppEnv = "managedEnvironment-rgrkibbe2470-82a8"

Write-Host "Starting persistent storage setup for Azure Resource Inventory..." -ForegroundColor Cyan

# 1. Create Storage Account
Write-Host "`n[1/6] Creating Storage Account: $storageAccountName" -ForegroundColor Yellow
az storage account create `
    --name $storageAccountName `
    --resource-group $resourceGroup `
    --location $location `
    --sku Standard_LRS `
    --kind StorageV2

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to create storage account" -ForegroundColor Red
    exit 1
}

# 2. Get Storage Account Key
Write-Host "`n[2/6] Retrieving storage account key..." -ForegroundColor Yellow
$storageKey = az storage account keys list `
    --account-name $storageAccountName `
    --resource-group $resourceGroup `
    --query "[0].value" `
    --output tsv

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to get storage key" -ForegroundColor Red
    exit 1
}

# 3. Create File Share
Write-Host "`n[3/6] Creating Azure File Share: $fileShareName" -ForegroundColor Yellow
az storage share create `
    --name $fileShareName `
    --account-name $storageAccountName `
    --account-key $storageKey `
    --quota 10

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to create file share" -ForegroundColor Red
    exit 1
}

# 4. Add Storage to Container App Environment
Write-Host "`n[4/6] Adding storage to Container App Environment..." -ForegroundColor Yellow
az containerapp env storage set `
    --name $containerAppEnv `
    --resource-group $resourceGroup `
    --storage-name "ari-persistent-data" `
    --azure-file-account-name $storageAccountName `
    --azure-file-account-key $storageKey `
    --azure-file-share-name $fileShareName `
    --access-mode ReadWrite

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to add storage to environment" -ForegroundColor Red
    exit 1
}

# 5. Create YAML configuration with volume mount
Write-Host "`n[5/6] Creating YAML configuration with volume mount..." -ForegroundColor Yellow

$yamlConfig = @"
properties:
  template:
    containers:
    - name: azure-resource-inventory
      image: rkazureinventory.azurecr.io/azure-resource-inventory:v6.24
      resources:
        cpu: 1
        memory: 2Gi
      volumeMounts:
      - volumeName: ari-data-volume
        mountPath: /data
    volumes:
    - name: ari-data-volume
      storageType: AzureFile
      storageName: ari-persistent-data
"@

$yamlFile = "container-app-with-storage.yaml"
$yamlConfig | Out-File -FilePath $yamlFile -Encoding UTF8

# 6. Apply YAML configuration
Write-Host "`n[6/6] Updating Container App with persistent storage and v6.24..." -ForegroundColor Yellow
az containerapp update `
    --name $containerAppName `
    --resource-group $resourceGroup `
    --yaml $yamlFile

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to update container app with volume mount" -ForegroundColor Red
    Write-Host "WARNING: Storage is created but not mounted. You may need to manually configure the volume mount." -ForegroundColor Yellow
    exit 1
}

Write-Host "`nSUCCESS: Persistent storage successfully configured!" -ForegroundColor Green
Write-Host "`nStorage Details:" -ForegroundColor Cyan
Write-Host "   Storage Account: $storageAccountName"
Write-Host "   File Share: $fileShareName"
Write-Host "   Mount Point: /data"
Write-Host "   Access Mode: ReadWrite"
Write-Host "   Image: rkazureinventory.azurecr.io/azure-resource-inventory:v6.24"
Write-Host "`nContainer App is restarting with new configuration..."
Write-Host "Job persistence will now survive container restarts."
Write-Host "Debug mode is now enabled by default for better visibility."

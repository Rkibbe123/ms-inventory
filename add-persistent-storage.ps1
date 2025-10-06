# Add persistent storage to Azure Container App
# This will create an Azure Storage Account and mount it to /data for job persistence

$resourceGroup = "rg-rkibbe-2470"
$location = "eastus"
$storageAccountName = "ariinventorystorage$(Get-Random -Minimum 1000 -Maximum 9999)"
$fileShareName = "ari-data"
$containerAppName = "azure-resource-inventory"
$containerAppEnv = "managedEnvironment-rgrkibbe2470-82a8"

Write-Host "🚀 Setting up persistent storage for Azure Resource Inventory..." -ForegroundColor Cyan

# 1. Create Storage Account
Write-Host "`n1️⃣ Creating Storage Account: $storageAccountName" -ForegroundColor Yellow
az storage account create `
    --name $storageAccountName `
    --resource-group $resourceGroup `
    --location $location `
    --sku Standard_LRS `
    --kind StorageV2

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to create storage account" -ForegroundColor Red
    exit 1
}

# 2. Get Storage Account Key
Write-Host "`n2️⃣ Retrieving storage account key..." -ForegroundColor Yellow
$storageKey = az storage account keys list `
    --account-name $storageAccountName `
    --resource-group $resourceGroup `
    --query "[0].value" `
    --output tsv

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to get storage key" -ForegroundColor Red
    exit 1
}

# 3. Create File Share
Write-Host "`n3️⃣ Creating Azure File Share: $fileShareName" -ForegroundColor Yellow
az storage share create `
    --name $fileShareName `
    --account-name $storageAccountName `
    --account-key $storageKey `
    --quota 10

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to create file share" -ForegroundColor Red
    exit 1
}

# 4. Add Storage to Container App Environment
Write-Host "`n4️⃣ Adding storage to Container App Environment..." -ForegroundColor Yellow
az containerapp env storage set `
    --name $containerAppEnv `
    --resource-group $resourceGroup `
    --storage-name "ari-persistent-data" `
    --azure-file-account-name $storageAccountName `
    --azure-file-account-key $storageKey `
    --azure-file-share-name $fileShareName `
    --access-mode ReadWrite

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to add storage to environment" -ForegroundColor Red
    exit 1
}

# 5. Update Container App to mount the storage
Write-Host "`n5️⃣ Updating Container App to mount persistent storage..." -ForegroundColor Yellow

# Update with volume mount
az containerapp update `
    --name $containerAppName `
    --resource-group $resourceGroup `
    --set-env-vars "STORAGE_MOUNTED=true" `
    --cpu 1 `
    --memory 2Gi

# Add volume mount (this requires YAML update)
Write-Host "`n6️⃣ Creating YAML configuration with volume mount..." -ForegroundColor Yellow

$yamlConfig = @"
properties:
  template:
    containers:
    - name: azure-resource-inventory
      image: rkazureinventory.azurecr.io/azure-resource-inventory:v6.23
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

# Apply YAML configuration
az containerapp update `
    --name $containerAppName `
    --resource-group $resourceGroup `
    --yaml $yamlFile

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to update container app with volume mount" -ForegroundColor Red
    Write-Host "⚠️  Storage is created but not mounted. You may need to manually configure the volume mount." -ForegroundColor Yellow
    exit 1
}

Write-Host "`n✅ Persistent storage successfully configured!" -ForegroundColor Green
Write-Host "`n📊 Storage Details:" -ForegroundColor Cyan
Write-Host "   Storage Account: $storageAccountName"
Write-Host "   File Share: $fileShareName"
Write-Host "   Mount Point: /data"
Write-Host "   Access Mode: ReadWrite"
Write-Host "`n🔄 Container App is restarting with new configuration..."
Write-Host "   Job persistence will now survive container restarts."

# Mount existing storage to Container App and update to v6.24
# Storage is already configured in the environment, we just need to mount it

$resourceGroup = "rg-rkibbe-2470"
$containerAppName = "azure-resource-inventory"

Write-Host "Updating Container App to mount storage and use v6.24..." -ForegroundColor Cyan

# Create YAML configuration with volume mount
Write-Host "`nCreating configuration with persistent storage mount..." -ForegroundColor Yellow

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
      storageName: ari-data
"@

$yamlFile = "container-app-with-storage.yaml"
$yamlConfig | Out-File -FilePath $yamlFile -Encoding UTF8

Write-Host "Configuration file created: $yamlFile" -ForegroundColor Green
Write-Host "`nApplying configuration to Container App..." -ForegroundColor Yellow

# Apply YAML configuration
az containerapp update `
    --name $containerAppName `
    --resource-group $resourceGroup `
    --yaml $yamlFile

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nERROR: Failed to update container app" -ForegroundColor Red
    Write-Host "You can manually apply this in the Azure Portal:" -ForegroundColor Yellow
    Write-Host "1. Go to Container App -> Containers -> Edit and deploy" -ForegroundColor Yellow
    Write-Host "2. Update image to: rkazureinventory.azurecr.io/azure-resource-inventory:v6.24" -ForegroundColor Yellow
    Write-Host "3. Add volume mount: Volume=ari-data, Mount path=/data" -ForegroundColor Yellow
    exit 1
}

Write-Host "`nSUCCESS: Configuration complete!" -ForegroundColor Green
Write-Host "`nWhat was updated:" -ForegroundColor Cyan
Write-Host "   Image: v6.24 (Debug mode enabled)"
Write-Host "   Storage: ari-data mounted at /data"
Write-Host "   Job persistence: ENABLED"
Write-Host "`nContainer App is restarting (takes 2-3 minutes)..."
Write-Host "Once restarted, your ARI jobs will survive container restarts!"

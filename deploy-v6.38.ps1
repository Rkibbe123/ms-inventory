# Deploy Testing Mode v6.38
Write-Host "`n=== Deploying Testing Mode v6.38 ===" -ForegroundColor Cyan
Write-Host "This version includes ONLY Compute module for testing`n" -ForegroundColor Yellow

# Update Container App
Write-Host "Updating Container App to v6.38..." -ForegroundColor Yellow
az containerapp update `
    --name ms-inventory `
    --resource-group rg-rkibbe-2470 `
    --image rkazureinventory.azurecr.io/azure-resource-inventory:v6.38

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ Deployment successful!" -ForegroundColor Green
    Write-Host "`n📋 What to expect:" -ForegroundColor Cyan
    Write-Host "  - Only Compute module will be processed" -ForegroundColor White
    Write-Host "  - Should complete in 3-5 minutes" -ForegroundColor White
    Write-Host "  - Look for '🧪 TESTING MODE' in logs" -ForegroundColor White
    Write-Host "`n🌐 Test at: https://azure-resource-inventory.ambitiousbeach-c62b6a92.eastus.azurecontainerapps.io" -ForegroundColor Cyan
    Write-Host "`n📊 Monitor with: .\watch-progress.ps1" -ForegroundColor Yellow
} else {
    Write-Host "`n❌ Deployment failed!" -ForegroundColor Red
    Write-Host "Try running the az containerapp update command manually" -ForegroundColor Yellow
}

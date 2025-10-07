# Build and Deploy v6.39 - FINAL Testing Mode Version
# This version FINALLY uses local modified modules instead of PowerShell Gallery!

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   Building v6.39 - Testing Mode with Local Modules        ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

Write-Host "🔧 What's Fixed in v6.39:" -ForegroundColor Yellow
Write-Host "  ✅ Uses LOCAL modified modules (not PowerShell Gallery)" -ForegroundColor Green
Write-Host "  ✅ Only processes Compute module" -ForegroundColor Green
Write-Host "  ✅ Skips extra jobs (Draw.io, Security, Policy, Advisory)" -ForegroundColor Green
Write-Host "  ✅ Increased timeouts (3 min per job)" -ForegroundColor Green
Write-Host "  ✅ Testing mode indicators will appear!" -ForegroundColor Green
Write-Host ""

# Step 1: Build
Write-Host "📦 Step 1: Building Docker image..." -ForegroundColor Cyan
docker build -t rkazureinventory.azurecr.io/azure-resource-inventory:v6.39 .

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n❌ Docker build failed!" -ForegroundColor Red
    Write-Host "Retrying once..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    docker build -t rkazureinventory.azurecr.io/azure-resource-inventory:v6.39 .
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n❌ Build failed again. Check network connection." -ForegroundColor Red
        exit 1
    }
}

Write-Host "✅ Build successful!" -ForegroundColor Green
Write-Host ""

# Step 2: Push
Write-Host "📤 Step 2: Pushing to Azure Container Registry..." -ForegroundColor Cyan
docker push rkazureinventory.azurecr.io/azure-resource-inventory:v6.39

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n❌ Docker push failed!" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Push successful!" -ForegroundColor Green
Write-Host ""

# Step 3: Update Container App
Write-Host "🔄 Step 3: Updating Azure Container App..." -ForegroundColor Cyan
az containerapp update `
    --name ms-inventory `
    --resource-group rg-rkibbe-2470 `
    --image rkazureinventory.azurecr.io/azure-resource-inventory:v6.39

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║              ✅ DEPLOYMENT SUCCESSFUL!                     ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "🎯 What to expect now:" -ForegroundColor Cyan
    Write-Host "  1. Start a new scan from the web interface" -ForegroundColor White
    Write-Host "  2. Look for these indicators:" -ForegroundColor Yellow
    Write-Host "     • '🧪 TESTING MODE: Using local modified AzureResourceInventory module'" -ForegroundColor Gray
    Write-Host "     • '🧪 TESTING MODE: Only processing Compute module'" -ForegroundColor Gray
    Write-Host "     • 'Creating Job: Compute' (should be ONLY 1 job)" -ForegroundColor Gray
    Write-Host "     • '⏱️ TIMEOUT SETTINGS: Total=15 min, Per-Job=3 min'" -ForegroundColor Gray
    Write-Host "  3. Should complete in 3-5 minutes" -ForegroundColor White
    Write-Host ""
    Write-Host "🌐 Web Interface: https://azure-resource-inventory.ambitiousbeach-c62b6a92.eastus.azurecontainerapps.io" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "📊 Monitor with:" -ForegroundColor Yellow
    Write-Host "   .\watch-progress.ps1" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host "`n❌ Container App update failed!" -ForegroundColor Red
    Write-Host "You can try updating manually via Azure Portal" -ForegroundColor Yellow
}

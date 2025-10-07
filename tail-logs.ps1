# Tail Container Logs - Similar to "tail -f" for Azure Container Apps
# Shows the last 100 lines and follows new output

$CONTAINER_APP = "ms-inventory"
$RESOURCE_GROUP = "rg-rkibbe-2470"

Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║        Container Logs - Live Stream                        ║" -ForegroundColor Cyan
Write-Host "║        Press Ctrl+C to stop                                ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Starting log stream from container..." -ForegroundColor Yellow
Write-Host ""

# Stream logs with follow mode
az containerapp logs show `
    --name $CONTAINER_APP `
    --resource-group $RESOURCE_GROUP `
    --follow `
    --tail 100 `
    --type console

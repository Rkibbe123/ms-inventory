# Azure Resource Inventory - Monitoring Guide
# Quick reference for checking status while inventory is running

Write-Host @"
╔════════════════════════════════════════════════════════════════════════╗
║                                                                        ║
║       Azure Resource Inventory - Monitoring Options                   ║
║                                                                        ║
╚════════════════════════════════════════════════════════════════════════╝

🔍 QUICK STATUS CHECKS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Quick Overview (Shows status, jobs, and files)
   "@ -ForegroundColor Cyan

Write-Host "   .\check-status.ps1" -ForegroundColor Green

Write-Host @"

2. Live Progress Monitor (Auto-refreshing dashboard)
   "@ -ForegroundColor Cyan

Write-Host "   .\watch-progress.ps1" -ForegroundColor Green

Write-Host @"

3. View Container Logs (Last 100 lines, then follow)
   "@ -ForegroundColor Cyan

Write-Host "   .\tail-logs.ps1" -ForegroundColor Green

Write-Host @"

4. Detailed Job Information (PowerShell jobs breakdown)
   "@ -ForegroundColor Cyan

Write-Host "   .\get-job-details.ps1" -ForegroundColor Green

Write-Host @"


📊 ADVANCED OPTIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Stream Live Logs:
"@ -ForegroundColor Cyan

Write-Host "   .\check-status.ps1 -Stream" -ForegroundColor Green

Write-Host @"

Check Jobs Only:
"@ -ForegroundColor Cyan

Write-Host "   .\check-status.ps1 -Jobs" -ForegroundColor Green

Write-Host @"

Check Files Only:
"@ -ForegroundColor Cyan

Write-Host "   .\check-status.ps1 -Files" -ForegroundColor Green

Write-Host @"

Show Everything:
"@ -ForegroundColor Cyan

Write-Host "   .\check-status.ps1 -All" -ForegroundColor Green

Write-Host @"


🌐 WEB INTERFACE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Main Dashboard:
"@ -ForegroundColor Cyan

Write-Host "   https://azure-resource-inventory.ambitiousbeach-c62b6a92.eastus.azurecontainerapps.io" -ForegroundColor Blue

Write-Host @"

View Reports:
"@ -ForegroundColor Cyan

Write-Host "   https://azure-resource-inventory.ambitiousbeach-c62b6a92.eastus.azurecontainerapps.io/outputs" -ForegroundColor Blue

Write-Host @"

Check Files (Debug):
"@ -ForegroundColor Cyan

Write-Host "   https://azure-resource-inventory.ambitiousbeach-c62b6a92.eastus.azurecontainerapps.io/debug-files" -ForegroundColor Blue

Write-Host @"

Job Status API:
"@ -ForegroundColor Cyan

Write-Host "   https://azure-resource-inventory.ambitiousbeach-c62b6a92.eastus.azurecontainerapps.io/check-jobs" -ForegroundColor Blue

Write-Host @"


⚡ DIRECT AZURE CLI COMMANDS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

View recent logs (last 50 lines):
"@ -ForegroundColor Cyan

Write-Host @"
   az containerapp logs show \
      --name ms-inventory \
      --resource-group rg-rkibbe-2470 \
      --tail 50
"@ -ForegroundColor Gray

Write-Host @"

Stream live logs:
"@ -ForegroundColor Cyan

Write-Host @"
   az containerapp logs show \
      --name ms-inventory \
      --resource-group rg-rkibbe-2470 \
      --follow
"@ -ForegroundColor Gray

Write-Host @"

Get container status:
"@ -ForegroundColor Cyan

Write-Host @"
   az containerapp show \
      --name ms-inventory \
      --resource-group rg-rkibbe-2470 \
      --query "properties.runningStatus"
"@ -ForegroundColor Gray

Write-Host @"


📋 WHAT TO LOOK FOR
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Good Signs:
   • Container status: Running
   • PowerShell jobs progressing (completed count increasing)
   • New log entries appearing regularly
   • Files being generated in the output directory

⚠️  Warning Signs:
   • No log updates for > 5 minutes
   • High number of failed jobs
   • Container status: Stopped or Error

❌ Error Signs:
   • Authentication failures
   • All jobs in Failed state
   • No files generated after 30+ minutes


💡 TIPS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

• For best experience: Use "@ -ForegroundColor Cyan

Write-Host ".\watch-progress.ps1" -ForegroundColor Green -NoNewline

Write-Host @" - it auto-refreshes!

• Large environments can take 10-30 minutes
• Job count varies based on your Azure resources
• Some jobs may take longer than others (normal behavior)
• The web interface shows real-time progress with device code

"@ -ForegroundColor White

Write-Host "Press any key to close this guide..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

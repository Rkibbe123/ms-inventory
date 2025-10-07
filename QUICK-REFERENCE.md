# Quick Reference: Testing Mode Commands

## Deploy the Testing Version
```powershell
# Full automated deployment
.\quick-deploy.ps1

# OR manual steps if automated fails:
docker build -t rkazureinventory.azurecr.io/azure-resource-inventory:v6.27 .
docker push rkazureinventory.azurecr.io/azure-resource-inventory:v6.27
az containerapp update --name ms-inventory --resource-group rg-rkibbe-2470 --image rkazureinventory.azurecr.io/azure-resource-inventory:v6.27
```

## Start Test Scan
```
Open browser: https://azure-resource-inventory.ambitiousbeach-c62b6a92.eastus.azurecontainerapps.io
Click: "Run Invoke-ARI"
Complete device authentication
```

## Monitor Test Progress
```powershell
# Option 1: Live dashboard (recommended!)
.\watch-progress.ps1

# Option 2: Quick status check
.\check-status-simple.ps1

# Option 3: Stream container logs
az containerapp logs show --name ms-inventory --resource-group rg-rkibbe-2470 --follow

# Option 4: Web interface
# https://azure-resource-inventory.ambitiousbeach-c62b6a92.eastus.azurecontainerapps.io
```

## What to Look For

### ✅ Good Signs:
- "🧪 TESTING MODE: Only processing Compute module"
- "Creating Job: Compute" 
- "Resource Jobs Still Running: 1" (not 160+)
- Job completes in 3-5 minutes
- Excel file appears in /outputs

### ⚠️ Warning Signs:
- No log output for 2+ minutes
- Job timeout after 3 minutes
- Error messages in logs

## View Results
```
# Web interface
https://azure-resource-inventory.ambitiousbeach-c62b6a92.eastus.azurecontainerapps.io/outputs

# Or check via PowerShell
.\check-status-simple.ps1
```

## Restore Full Functionality
```powershell
# See detailed instructions in:
code TESTING-MODE-CHANGES.md

# Quick revert:
git checkout Modules/Private/2.ProcessingFunctions/Start-ARIProcessJob.ps1
git checkout Modules/Private/2.ProcessingFunctions/Start-ARIExtraJobs.ps1
git checkout Modules/Public/PublicFunctions/Jobs/Wait-ARIJob.ps1

# Then rebuild and deploy
.\quick-deploy.ps1
```

## Documentation
- `TESTING-MODE-SUMMARY.md` - Overview of changes
- `TESTING-MODE-CHANGES.md` - Detailed technical docs  
- `HOW-TO-MONITOR.md` - Monitoring guide
- `MONITORING-GUIDE.ps1` - Interactive help

---
**Ready to test!** 🚀

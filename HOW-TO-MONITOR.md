# Monitoring Your Azure Resource Inventory While It's Running

## Quick Answer: 5 Ways to Check Status

### 🎯 Method 1: Simple Web Browser (EASIEST)
Just open your browser to:
- **Main Status Page**: https://azure-resource-inventory.ambitiousbeach-c62b6a92.eastus.azurecontainerapps.io
- **View Reports**: https://azure-resource-inventory.ambitiousbeach-c62b6a92.eastus.azurecontainerapps.io/outputs  
- **Debug Info**: https://azure-resource-inventory.ambitiousbeach-c62b6a92.eastus.azurecontainerapps.io/check-jobs

The web interface shows real-time progress with auto-updating status!

---

### 📊 Method 2: PowerShell Status Scripts (RECOMMENDED)

I've created several monitoring scripts for you:

#### **Quick Status Check:**
```powershell
.\check-status-simple.ps1
```
Shows: Job count, progress %, generated files

#### **Live Progress Monitor (Auto-refreshing dashboard):**
```powershell
.\watch-progress.ps1
```
Shows: Real-time updates every 5 seconds with progress bars

#### **Detailed Job Information:**
```powershell
.\get-job-details.ps1
```
Shows: Full breakdown of each PowerShell job with timing

#### **View Full Guide:**
```powershell
.\MONITORING-GUIDE.ps1
```
Shows: Complete reference of all monitoring options

---

### 🔍 Method 3: Azure CLI Direct Commands

**Check Container Status:**
```powershell
az containerapp show `
  --name ms-inventory `
  --resource-group rg-rkibbe-2470 `
  --query "properties.runningStatus"
```

**View Recent Logs (last 50 lines):**
```powershell
az containerapp logs show `
  --name ms-inventory `
  --resource-group rg-rkibbe-2470 `
  --tail 50
```

**Stream Live Logs (follow mode):**
```powershell
az containerapp logs show `
  --name ms-inventory `
  --resource-group rg-rkibbe-2470 `
  --follow
```

---

### 🌐 Method 4: HTTP API Endpoints

You can use `Invoke-WebRequest` or `curl` to check status:

**Check PowerShell Jobs:**
```powershell
Invoke-WebRequest -Uri "https://azure-resource-inventory.ambitiousbeach-c62b6a92.eastus.azurecontainerapps.io/check-jobs" | Select-Object -ExpandProperty Content
```

**Check Generated Files:**
```powershell
Invoke-WebRequest -Uri "https://azure-resource-inventory.ambitiousbeach-c62b6a92.eastus.azurecontainerapps.io/debug-files" | Select-Object -ExpandProperty Content
```

---

### 📱 Method 5: Azure Portal

1. Go to https://portal.azure.com
2. Navigate to **Resource Groups** → **rg-rkibbe-2470**
3. Click on **ms-inventory** (Container App)
4. Select **Log stream** from the left menu
5. Watch logs in real-time!

---

## What To Look For

### ✅ Good Signs:
- **"Resource Jobs Still Running: X"** - Jobs are processing
- **Job count decreasing** - Jobs are completing
- **Files appearing in /outputs** - Reports are being generated
- **Regular log updates** - Activity is happening

### ⏳ Normal Behavior:
- **Takes 10-30 minutes** for large environments
- **Some jobs take longer** than others
- **Log output pauses** during processing (normal)
- **"Connecting to stream..."** may show while waiting for output

### ⚠️ Warning Signs:
- **No updates for 5+ minutes** - May be stuck
- **High failed job count** - Check for errors
- **Authentication errors** - Need to re-authenticate

### ❌ Problems:
- **Container stopped** - Needs restart
- **All jobs failed** - Check permissions
- **No files after 30+ min** - Check logs for errors

---

## Troubleshooting Tips

### If Nothing is Showing:
1. Check if inventory scan has been started from web interface
2. Verify container is running: `.\check-status-simple.ps1`
3. Check for errors in logs: `az containerapp logs show --name ms-inventory --resource-group rg-rkibbe-2470 --tail 100`

### If It Seems Stuck:
1. Watch the progress: `.\watch-progress.ps1`
2. Look for "Resource Jobs Still Running" messages
3. Be patient - large environments can take 30+ minutes
4. The process may appear quiet during processing phases

### If You See Errors:
1. Get detailed job info: `.\get-job-details.ps1`
2. Check container logs for stack traces
3. Verify Azure permissions for the managed identity
4. Try restarting the scan from the web interface

---

## Current Status of Your Scan

Based on your screenshot earlier, your scan showed:
- ✅ Jobs were being created successfully
- ✅ Processing was active (160 jobs running)
- ✅ Various resource types were being scanned (Analytics, ComputeD, DatabaseD, etc.)
- ⏳ Scan had been running for 2+ minutes

**This is normal!** The scan is progressing. Give it 10-30 minutes to complete.

---

## Quick Commands Summary

```powershell
# Quick status
.\check-status-simple.ps1

# Live monitoring (best option!)
.\watch-progress.ps1

# Stream logs
az containerapp logs show --name ms-inventory --resource-group rg-rkibbe-2470 --follow

# Check in browser
start https://azure-resource-inventory.ambitiousbeach-c62b6a92.eastus.azurecontainerapps.io
```

---

## Need Help?

All monitoring scripts are in your current directory:
- `check-status-simple.ps1` - Quick overview
- `watch-progress.ps1` - Live dashboard
- `get-job-details.ps1` - Detailed job info
- `tail-logs.ps1` - Stream logs
- `MONITORING-GUIDE.ps1` - Full reference guide

Just run any of them to start monitoring!

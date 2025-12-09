# Quick Reference: Azure File Share Cleanup & Diagram Validation

## 🎯 Quick Setup

### Enable File Share Cleanup

**Required Environment Variables:**
```bash
AZURE_STORAGE_ACCOUNT=mystorageaccount
AZURE_STORAGE_KEY=abc123...
AZURE_FILE_SHARE=ari-data
```

**Via Azure CLI:**
```bash
# Get storage key
STORAGE_KEY=$(az storage account keys list \
  --account-name mystorageaccount \
  --resource-group my-rg \
  --query "[0].value" -o tsv)

# Configure container app
az containerapp update \
  --name azure-resource-inventory \
  --resource-group my-rg \
  --set-env-vars \
    AZURE_STORAGE_ACCOUNT=mystorageaccount \
    AZURE_STORAGE_KEY=$STORAGE_KEY \
    AZURE_FILE_SHARE=ari-data
```

**Via Portal:**
1. Go to Container App → **Environment variables**
2. Add the three variables above
3. Mark `AZURE_STORAGE_KEY` as **Secret**
4. Click **Save** and restart

**Quick Validation:**
```bash
# Verify configuration
az containerapp show \
  --name azure-resource-inventory \
  --resource-group my-rg \
  --query properties.template.containers[0].env

# Trigger test job and check logs
az containerapp logs show \
  --name azure-resource-inventory \
  --resource-group my-rg \
  --follow
```

## 🔍 How to Verify

### Check Cleanup is Working

**Success indicators in logs:**
```
[INFO] Importing Az.Storage module...
[SUCCESS] Az.Storage module loaded successfully
[INFO] Creating storage context...
[SUCCESS] Storage context created successfully
[INFO] Testing network connectivity to storage account...
[SUCCESS] Network connectivity verified
[INFO] Listing contents of file share...
[INFO] Found X items in file share
[INFO] Items to delete: X
[SUCCESS] Successfully deleted: filename
[INFO] Cleanup Statistics:
[SUCCESS]   Items deleted: X
[SUCCESS] CLEANUP COMPLETED SUCCESSFULLY
```

**If not configured:**
```
⚠️  Azure Storage environment variables not configured
File share cleanup is DISABLED because required environment
variables are not set. ARI will proceed without cleanup.
```

**If cleanup fails:**
```
❌ CLEANUP FAILED - BLOCKING ARI EXECUTION
File share cleanup failed with exit code: 1
🚫 CRITICAL ERROR: ARI execution cannot proceed
```

### Verify Protected Items

**Test protected folder preservation:**
```bash
# Create test files
az storage file upload --share-name ari-data --source test.txt --account-name $STORAGE_ACCOUNT

# Create protected folder
az storage directory create --name .jobs --share-name ari-data --account-name $STORAGE_ACCOUNT

# Trigger cleanup (via ARI job)

# Verify: .jobs should remain, test.txt should be deleted
az storage file list --share-name ari-data --account-name $STORAGE_ACCOUNT
```

### Check Diagram Generation

**Success:**
```
✅ Found 3 diagram file(s):
   📊 AzureResourceInventory_Diagram_*.xml
```

**Warning:**
```
⚠️  WARNING: No diagram files found!
```

## 🛠️ Troubleshooting

### Cleanup Not Working

**1. Verify environment variables are set:**
```bash
az containerapp show \
  --name azure-resource-inventory \
  --resource-group my-rg \
  --query properties.template.containers[0].env
```
Expected: All three variables (AZURE_STORAGE_ACCOUNT, AZURE_STORAGE_KEY, AZURE_FILE_SHARE) should be present

**2. Test storage account access:**
```bash
# Check account exists
az storage account show \
  --name mystorageaccount \
  --resource-group my-rg

# Test key is valid
az storage share list \
  --account-name mystorageaccount \
  --account-key $STORAGE_KEY
```

**3. Verify file share exists:**
```bash
az storage share show \
  --name ari-data \
  --account-name mystorageaccount \
  --account-key $STORAGE_KEY
```
If missing, create it:
```bash
az storage share create \
  --name ari-data \
  --account-name mystorageaccount \
  --account-key $STORAGE_KEY \
  --quota 100
```

**4. Check network/firewall rules:**
```bash
az storage account show \
  --name mystorageaccount \
  --resource-group my-rg \
  --query networkRuleSet
```
If default action is "Deny", add container subnet or allow all networks

**5. Review detailed logs:**
```bash
az containerapp logs show \
  --name azure-resource-inventory \
  --resource-group my-rg \
  --tail 1000 | grep -A 50 "CLEANUP"
```

### Cleanup Fails with Authentication Error

**Symptom:** `Failed to create storage context: (403) Forbidden`

**Solution:**
```bash
# Get fresh storage key
STORAGE_KEY=$(az storage account keys list \
  --account-name mystorageaccount \
  --resource-group my-rg \
  --query "[0].value" -o tsv)

# Update container app
az containerapp update \
  --name azure-resource-inventory \
  --resource-group my-rg \
  --set-env-vars AZURE_STORAGE_KEY=$STORAGE_KEY
```

### Cleanup Blocks ARI Execution

**This is expected behavior when cleanup is configured and fails.**

**To temporarily disable cleanup:**
```bash
# Remove cleanup environment variables
az containerapp update \
  --name azure-resource-inventory \
  --resource-group my-rg \
  --remove-env-vars \
    AZURE_STORAGE_ACCOUNT \
    AZURE_STORAGE_KEY \
    AZURE_FILE_SHARE

# WARNING: Old files will accumulate without cleanup
```

**Better approach - Fix the underlying issue:**
1. Review logs for specific error
2. Follow troubleshooting steps above
3. Re-enable cleanup once fixed

### No Diagrams Generated

**Possible causes:**
- No network resources (VNets, NSGs) in your Azure subscription
- Permissions issues with Resource Graph queries
- ARI module error during diagram generation

**How to diagnose:**
1. Check ARI execution logs for diagram-related errors
2. Verify network resources exist: `az network vnet list`
3. Check Resource Graph access: `az graph query --graph-query "Resources | take 1"`

### View Container Logs

```bash
# View recent logs
az containerapp logs show \
  --name azure-resource-inventory \
  --resource-group my-rg \
  --tail 100

# Stream logs in real-time
az containerapp logs show \
  --name azure-resource-inventory \
  --resource-group my-rg \
  --follow
```

## 📊 Expected Behavior

### Workflow
1. ✅ User starts ARI run
2. ✅ System checks for cleanup env vars
3. ✅ If set: Cleans file share
4. ✅ Authenticates to Azure
5. ✅ Runs Invoke-ARI (diagrams enabled by default)
6. ✅ Validates diagram generation
7. ✅ Shows results

### Files Generated
- `AzureResourceInventory_Report_*.xlsx` - Excel report
- `AzureResourceInventory_Diagram_*.xml` - Network diagram (Draw.io)

## 🔐 Security Best Practices

1. **Use Key Vault for Storage Keys:**
   ```bash
   az containerapp secret set \
     --name azure-resource-inventory \
     --resource-group my-rg \
     --secrets storage-key=keyvault://...
   ```

2. **Use Managed Identity (when possible):**
   - Prefer Managed Identity over storage keys
   - Grant "Storage Blob Data Contributor" role

3. **Restrict Network Access:**
   ```bash
   az storage account update \
     --name mystorageaccount \
     --resource-group my-rg \
     --default-action Deny
   ```

## 📚 Related Documentation

- [Container Deployment Guide](CONTAINER-DEPLOYMENT.md) - Full deployment guide
- [PowerShell Scripts](powershell/README.md) - Script documentation
- [Azure Container Apps Docs](https://docs.microsoft.com/azure/container-apps/)

## 💡 Tips

1. **First Run**: File share may be empty, cleanup will report "already empty"
2. **Cleanup Errors**: ARI continues even if cleanup fails (non-blocking)
3. **Diagram Files**: Can be opened with [Draw.io](https://www.draw.io)
4. **Storage Quota**: 10GB recommended for file share quota
5. **Retention**: Enable cleanup to prevent storage bloat

## 🆘 Getting Help

If you encounter issues:

1. Check container logs (see above)
2. Verify environment variables are set correctly
3. Test storage account access with Azure CLI
4. Review the [troubleshooting section](CONTAINER-DEPLOYMENT.md#troubleshooting) in the deployment guide
5. Open an issue on GitHub with logs and error messages

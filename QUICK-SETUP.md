# Quick Reference: Azure File Share Cleanup & Diagram Validation

## 🎯 Quick Setup

### Enable File Share Cleanup

Set these environment variables in your Azure Container App:

```bash
AZURE_STORAGE_ACCOUNT=mystorageaccount
AZURE_STORAGE_KEY=abc123...
AZURE_FILE_SHARE=ari-data
```

**Via Azure CLI:**
```bash
az containerapp update \
  --name azure-resource-inventory \
  --resource-group my-rg \
  --set-env-vars \
    AZURE_STORAGE_ACCOUNT=mystorageaccount \
    AZURE_STORAGE_KEY=secretvalue \
    AZURE_FILE_SHARE=ari-data
```

**Via Portal:**
1. Go to Container App → Environment variables
2. Add the three variables above
3. Save and restart

## 🔍 How to Verify

### Check Cleanup is Working

**Look for these logs:**
```
🧹 Checking for Azure File Share cleanup configuration...
Azure Storage configuration found. Running file share cleanup...
✅ File share cleanup completed successfully
```

**If not configured:**
```
⚠️  Azure Storage environment variables not set. Skipping file share cleanup.
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

1. **Verify environment variables are set:**
   ```bash
   az containerapp show \
     --name azure-resource-inventory \
     --resource-group my-rg \
     --query properties.template.containers[0].env
   ```

2. **Check storage account access:**
   ```bash
   az storage account show \
     --name mystorageaccount \
     --resource-group my-rg
   ```

3. **Verify file share exists:**
   ```bash
   az storage share show \
     --name ari-data \
     --account-name mystorageaccount
   ```

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

# Azure Container Deployment Guide

## Overview

This guide explains how to deploy Azure Resource Inventory (ARI) as a containerized web application with Azure File Share integration for persistent storage.

## Features

### 🧹 Automatic File Share Cleanup

Before each ARI execution, the container can automatically clean up the Azure File Share to ensure a fresh state for report generation. This prevents accumulation of old reports and diagrams.

**Configuration:**

To enable automatic cleanup, set the following environment variables in your container app:

- `AZURE_STORAGE_ACCOUNT`: The name of your Azure Storage Account
- `AZURE_STORAGE_KEY`: The access key for your Azure Storage Account
- `AZURE_FILE_SHARE`: The name of the Azure File Share to clean

**Example Container App Configuration:**

```yaml
properties:
  template:
    containers:
    - name: azure-resource-inventory
      image: rkazureinventory.azurecr.io/azure-resource-inventory:latest
      env:
      - name: AZURE_STORAGE_ACCOUNT
        value: "mystorageaccount"
      - name: AZURE_STORAGE_KEY
        secretRef: storage-key
      - name: AZURE_FILE_SHARE
        value: "ari-data"
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
```

**Behavior:**

- If the environment variables are set, the cleanup script runs automatically before each ARI execution
- The script recursively deletes all files and directories from the file share root
- **Protected folders** (`.jobs`) are automatically excluded from deletion to preserve job state
- After cleanup, the script verifies success by listing remaining files
- If the environment variables are not set, cleanup is skipped (no errors)
- Cleanup failures are logged but don't prevent ARI execution from continuing

### 📊 Diagram Generation & Validation

**Default Behavior:**

- Diagram generation is **enabled by default**
- The `-SkipDiagram` parameter is NOT used
- Diagrams are generated in Draw.io XML format for network topology visualization

**Post-Execution Validation:**

After ARI completes, the system automatically:

1. ✅ Checks if diagram files were generated
2. ✅ Lists all diagram files found (typically named with "Diagram" in the filename)
3. ⚠️ Warns if no diagram files are found
4. 📋 Provides troubleshooting guidance if diagrams are missing

**Expected Diagram Files:**

- Format: `AzureResourceInventory_Diagram_yyyy-MM-dd_HH_mm.xml`
- Location: Same directory as Excel reports (`/data/AzureResourceInventory`)
- Can be opened with: [Draw.io](https://www.draw.io)

**Troubleshooting Missing Diagrams:**

If diagrams are not generated:

1. **Check Network Resources**: Diagram generation requires network resources (VNets, NSGs, etc.) in your Azure environment
2. **Review Logs**: Check the ARI execution logs for diagram-related errors
3. **Verify Permissions**: Ensure the service principal has read access to network resources
4. **Check Resource Graph**: Diagram generation uses Azure Resource Graph queries

### 🔄 Complete Workflow

1. **User Triggers Inventory**: User initiates ARI run via web interface
2. **Authentication**: Azure CLI device login (or Managed Identity)
3. **Cleanup (Optional)**: If configured, clears Azure File Share
4. **ARI Execution**: Runs Invoke-ARI with diagram generation enabled
5. **File Validation**: Checks for generated Excel reports
6. **Diagram Validation**: Verifies diagram files were created
7. **Results Display**: Shows download links for all generated files

## Manual Cleanup Script

The cleanup script can also be run manually:

```bash
# Using PowerShell
pwsh /app/powershell/clear-azure-fileshare.ps1 \
    -StorageAccountName "mystorageaccount" \
    -StorageAccountKey "abc123..." \
    -FileShareName "ari-data"
```

**Script Parameters:**

- `-StorageAccountName` (Required): Azure Storage Account name
- `-StorageAccountKey` (Required): Storage Account access key
- `-FileShareName` (Required): File Share name to clean

## Deployment Steps

### 1. Create Storage Account

```powershell
az storage account create \
    --name mystorageaccount \
    --resource-group my-rg \
    --location eastus \
    --sku Standard_LRS \
    --kind StorageV2
```

### 2. Create File Share

```powershell
$storageKey = az storage account keys list \
    --account-name mystorageaccount \
    --resource-group my-rg \
    --query "[0].value" \
    --output tsv

az storage share create \
    --name ari-data \
    --account-name mystorageaccount \
    --account-key $storageKey \
    --quota 10
```

### 3. Configure Container App Environment

```powershell
az containerapp env storage set \
    --name my-container-env \
    --resource-group my-rg \
    --storage-name "ari-persistent-data" \
    --azure-file-account-name mystorageaccount \
    --azure-file-account-key $storageKey \
    --azure-file-share-name ari-data \
    --access-mode ReadWrite
```

### 4. Deploy Container App

```powershell
az containerapp create \
    --name azure-resource-inventory \
    --resource-group my-rg \
    --environment my-container-env \
    --image rkazureinventory.azurecr.io/azure-resource-inventory:latest \
    --target-port 8000 \
    --ingress external \
    --cpu 1 --memory 2Gi \
    --env-vars \
        AZURE_STORAGE_ACCOUNT=mystorageaccount \
        AZURE_STORAGE_KEY=$storageKey \
        AZURE_FILE_SHARE=ari-data
```

## Monitoring & Logs

### Check Cleanup Logs

```bash
# Container logs will show cleanup activity
az containerapp logs show \
    --name azure-resource-inventory \
    --resource-group my-rg \
    --follow
```

Look for these log messages:

**Cleanup Starting:**
- `🧹 Checking for Azure File Share cleanup configuration...`
- `Azure Storage configuration found. Running file share cleanup...`

**Cleanup Progress:**
- `Connecting to Azure Storage...`
- `✅ Connected to storage account successfully`
- `Found X items in file share`
- `🔒 Protected folder will be preserved: .jobs`
- `Items to delete: X`
- `Deleting file: filename` or `Deleting directory: dirname`

**Cleanup Verification:**
- `🔍 Verifying cleanup...`
- `📁 Remaining items in file share: X`
- `✅ All non-protected items were successfully deleted`

**Cleanup Complete:**
- `✅ File share cleanup completed successfully`

**Cleanup Errors:**
- `⚠️ File share cleanup encountered errors (exit code: X)`
- `❌ ERROR: Failed to clear file share`

### Check Diagram Generation

After ARI completes, logs will show:

- `🔍 Checking for diagram files...`
- `✅ Found X diagram file(s):` (if successful)
- `⚠️ WARNING: No diagram files found!` (if missing)

## Security Considerations

1. **Storage Keys**: Use Azure Key Vault or Container App secrets for storage keys
2. **Managed Identity**: Prefer Managed Identity over storage keys when possible
3. **Network Security**: Configure network rules on storage account if needed
4. **RBAC**: Grant minimal required permissions (Storage Blob Data Contributor)

## Best Practices

1. **Regular Cleanup**: Enable automatic cleanup to prevent storage bloat
2. **Monitoring**: Set up alerts for failed cleanup operations
3. **Backup**: Consider backing up important reports before cleanup
4. **Resource Quotas**: Allocate sufficient file share quota (10GB recommended)
5. **Diagram Validation**: Monitor logs for diagram generation warnings

## Troubleshooting

### Cleanup Fails

**Symptoms:**
- Container logs show: `❌ ERROR: Failed to clear file share`
- Old files continue to accumulate in file share
- Cleanup script exits with non-zero code

**Diagnostic Steps:**

```powershell
# 1. Verify storage account exists and is accessible
az storage account show \
    --name mystorageaccount \
    --resource-group my-rg

# 2. List file share contents to see what's there
az storage file list \
    --share-name ari-data \
    --account-name mystorageaccount \
    --account-key $storageKey

# 3. Test storage account key validity
az storage account keys list \
    --account-name mystorageaccount \
    --resource-group my-rg

# 4. Check file share quota and usage
az storage share show \
    --name ari-data \
    --account-name mystorageaccount \
    --account-key $storageKey
```

**Common Causes:**

1. **Invalid Storage Account Key**
   - Solution: Regenerate key and update environment variable
   ```powershell
   $storageKey = az storage account keys list \
       --account-name mystorageaccount \
       --resource-group my-rg \
       --query "[0].value" \
       --output tsv
   ```

2. **File Share Does Not Exist**
   - Solution: Create the file share
   ```powershell
   az storage share create \
       --name ari-data \
       --account-name mystorageaccount \
       --account-key $storageKey
   ```

3. **Network Connectivity Issues**
   - Check if container can reach Azure Storage endpoints
   - Verify firewall rules on storage account
   - Solution: Add container subnet to storage account network rules

4. **Files Locked or In Use**
   - Files may be locked by another process
   - Solution: Check for concurrent ARI executions
   - Solution: Manually delete locked files via Azure Portal

5. **Insufficient Permissions**
   - Storage account key may lack permissions
   - Solution: Verify key is from correct storage account
   - Solution: Use primary or secondary key with full access

**Manual Cleanup:**

If automatic cleanup continues to fail, you can manually clean the file share:

```powershell
# Using Azure CLI
az storage file delete-batch \
    --source ari-data \
    --account-name mystorageaccount \
    --account-key $storageKey

# Or via Azure Portal
# Navigate to: Storage Account > File shares > ari-data > Browse
# Select files/folders and click Delete
```

**Verification After Fix:**

After resolving cleanup issues, verify it works:

```bash
# Run a test ARI execution and watch logs
az containerapp logs show \
    --name azure-resource-inventory \
    --resource-group my-rg \
    --follow

# Look for successful cleanup messages:
# ✅ File share cleanup completed successfully
# ✅ All non-protected items were successfully deleted
```

### Diagrams Not Generated

1. Check if environment has network resources
2. Review ARI execution logs for errors
3. Verify Resource Graph permissions
4. Ensure no `-SkipDiagram` parameter is passed

### Container Logs

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

## Additional Resources

- [Azure Container Apps Documentation](https://docs.microsoft.com/azure/container-apps/)
- [Azure Files Documentation](https://docs.microsoft.com/azure/storage/files/)
- [Azure Resource Inventory GitHub](https://github.com/microsoft/AzureResourceInventory)
- [Draw.io for Diagrams](https://www.draw.io)

# Azure File Share Cleanup Guide

## Overview

The Azure File Share cleanup functionality automatically cleans the persistent storage before each Azure Resource Inventory (ARI) execution. This ensures a fresh state for report generation and prevents accumulation of old files that could cause confusion or consume excessive storage.

## Table of Contents

- [Overview](#overview)
- [Why Cleanup is Important](#why-cleanup-is-important)
- [How It Works](#how-it-works)
- [Configuration](#configuration)
- [Protected Items](#protected-items)
- [Workflow](#workflow)
- [Features](#features)
- [Testing and Validation](#testing-and-validation)
- [Troubleshooting](#troubleshooting)
- [Advanced Usage](#advanced-usage)
- [Best Practices](#best-practices)

## Why Cleanup is Important

### Benefits of Automatic Cleanup

1. **Data Freshness**: Ensures only current reports are present in storage
2. **Prevents Confusion**: Eliminates outdated reports that might be downloaded by mistake
3. **Storage Efficiency**: Prevents unbounded growth of storage consumption
4. **Data Integrity**: Ensures consistency between job runs
5. **Cost Control**: Reduces storage costs by removing obsolete files

### What Happens Without Cleanup

Without automatic cleanup, your file share will accumulate:
- Old Excel reports from previous executions
- Outdated network diagrams
- Temporary files and artifacts
- Multiple versions of the same report

This can lead to:
- User confusion about which report is current
- Increased storage costs
- Potential storage capacity issues
- Difficulty finding the latest reports

## How It Works

### Execution Flow

1. **Pre-ARI Execution**: Cleanup runs automatically before ARI starts
2. **Configuration Check**: Verifies cleanup environment variables are set
3. **Pre-flight Validation**: Tests connectivity and credentials
4. **Protected Item Detection**: Identifies folders and files to preserve
5. **Item Deletion**: Recursively removes non-protected items with retry logic
6. **Verification**: Confirms successful cleanup
7. **Statistics Reporting**: Logs cleanup metrics
8. **ARI Execution**: Proceeds only if cleanup succeeds (or is disabled)

### Blocking Behavior

**IMPORTANT**: If cleanup is configured and fails, ARI execution is **blocked**. This is intentional to maintain data integrity.

- ✅ **Cleanup Success** → ARI proceeds normally
- ❌ **Cleanup Failure** → ARI execution blocked, job fails with detailed error message
- ⚪ **Cleanup Not Configured** → ARI proceeds without cleanup

## Configuration

### Required Environment Variables

To enable automatic cleanup, configure these environment variables in your Azure Container App:

| Variable | Description | Example |
|----------|-------------|---------|
| `AZURE_STORAGE_ACCOUNT` | Name of Azure Storage Account | `mystorageaccount` |
| `AZURE_STORAGE_KEY` | Access key for storage account | `abc123...` (sensitive) |
| `AZURE_FILE_SHARE` | Name of file share to clean | `ari-data` |

### Azure CLI Configuration

```bash
az containerapp update \
  --name azure-resource-inventory \
  --resource-group my-resource-group \
  --set-env-vars \
    AZURE_STORAGE_ACCOUNT=mystorageaccount \
    AZURE_FILE_SHARE=ari-data \
    AZURE_STORAGE_KEY=secretvalue
```

### Azure Portal Configuration

1. Navigate to your Container App in Azure Portal
2. Go to **Settings** → **Environment variables**
3. Click **+ Add** for each variable
4. Enter the variable name and value
5. Mark `AZURE_STORAGE_KEY` as **Secret**
6. Click **Apply** and restart the container

### Configuration via YAML

```yaml
properties:
  template:
    containers:
    - name: azure-resource-inventory
      image: your-registry/azure-resource-inventory:latest
      env:
      - name: AZURE_STORAGE_ACCOUNT
        value: "mystorageaccount"
      - name: AZURE_STORAGE_KEY
        secretRef: storage-account-key
      - name: AZURE_FILE_SHARE
        value: "ari-data"
      volumeMounts:
      - volumeName: ari-data-volume
        mountPath: /data
    volumes:
    - name: ari-data-volume
      storageType: AzureFile
      storageName: ari-persistent-data
```

### Verifying Configuration

Check that environment variables are set correctly:

```bash
az containerapp show \
  --name azure-resource-inventory \
  --resource-group my-resource-group \
  --query properties.template.containers[0].env
```

## Protected Items

The cleanup script preserves critical system folders and files to maintain job state and system integrity.

### Protected Folders

The following folders are **never deleted**:

| Folder | Purpose | Critical |
|--------|---------|----------|
| `.jobs` | Job persistence and state tracking | ✅ Yes |
| `.snapshots` | Azure Files snapshot directory | ✅ Yes |
| `$logs` | Azure Storage logs directory | ✅ Yes |
| `System Volume Information` | Windows system folder | ✅ Yes |

### Protected File Patterns

Files matching these patterns are **never deleted**:

| Pattern | Purpose | Example |
|---------|---------|---------|
| `*.lock` | Lock files indicating active processes | `process.lock` |
| `*.tmp` | Temporary files potentially in use | `upload.tmp` |
| `.gitkeep` | Placeholder files for empty directories | `.gitkeep` |

### Why Protection is Important

Protected items ensure:
- **Job continuity**: Job state persists across executions
- **System stability**: System folders remain intact
- **Process safety**: Active processes aren't disrupted
- **Data integrity**: Critical metadata is preserved

## Workflow

### Complete Job Execution Flow

```
User Triggers Job
       ↓
Authenticate to Azure
       ↓
╔════════════════════════════════╗
║   CLEANUP PHASE                ║
╠════════════════════════════════╣
║ 1. Check configuration         ║
║ 2. Validate connectivity       ║
║ 3. List file share contents    ║
║ 4. Identify protected items    ║
║ 5. Delete non-protected items  ║
║ 6. Retry failed deletions      ║
║ 7. Verify cleanup success      ║
║ 8. Report statistics           ║
╚════════════════════════════════╝
       ↓
  Success? ──No──→ [BLOCK JOB] → Error Message → User Troubleshoots
       ↓
      Yes
       ↓
╔════════════════════════════════╗
║   ARI EXECUTION PHASE          ║
╠════════════════════════════════╣
║ 1. Run Invoke-ARI cmdlet       ║
║ 2. Generate reports            ║
║ 3. Create diagrams             ║
║ 4. Validate output files       ║
╚════════════════════════════════╝
       ↓
Display Results to User
```

### Cleanup Log Example

```
[2025-12-09 14:30:00] [INFO] Importing Az.Storage module...
[2025-12-09 14:30:01] [SUCCESS] Az.Storage module loaded successfully
[2025-12-09 14:30:01] [INFO] Creating storage context...
[2025-12-09 14:30:02] [SUCCESS] Storage context created successfully
[2025-12-09 14:30:02] [INFO] Testing network connectivity to storage account...
[2025-12-09 14:30:03] [SUCCESS] Network connectivity verified
[2025-12-09 14:30:03] [INFO] Verifying file share exists and is accessible...
[2025-12-09 14:30:04] [SUCCESS] File share found and accessible
[2025-12-09 14:30:04] [INFO] Listing contents of file share...
[2025-12-09 14:30:05] [INFO] Found 15 items in file share
[2025-12-09 14:30:05] [INFO] Protected folder will be preserved: .jobs
[2025-12-09 14:30:05] [INFO] Items to delete: 14
[2025-12-09 14:30:05] [INFO] Protected items: 1
[2025-12-09 14:30:05] [INFO] Processing item 1/14: AzureResourceInventory_Report_2025-12-08.xlsx (file)
[2025-12-09 14:30:06] [SUCCESS] Successfully deleted: AzureResourceInventory_Report_2025-12-08.xlsx
...
[2025-12-09 14:30:25] [INFO] Verifying cleanup...
[2025-12-09 14:30:26] [INFO] Remaining items in file share: 1
[2025-12-09 14:30:26] [INFO]   - .jobs (Directory) [PROTECTED]
[2025-12-09 14:30:26] [SUCCESS] All non-protected items were successfully deleted
[2025-12-09 14:30:26] [INFO] Cleanup Statistics:
[2025-12-09 14:30:26] [INFO]   Total items found: 15
[2025-12-09 14:30:26] [SUCCESS]   Items deleted: 14
[2025-12-09 14:30:26] [INFO]   Protected items preserved: 1
[2025-12-09 14:30:26] [INFO]   Items failed: 0
[2025-12-09 14:30:26] [INFO]   Duration: 26.34 seconds
[2025-12-09 14:30:26] [SUCCESS] CLEANUP COMPLETED SUCCESSFULLY
```

## Features

### 1. Comprehensive Protection

- Multiple protected folder types
- Pattern-based file protection
- Safe for system and application files

### 2. Retry Logic

- 3 retry attempts for transient failures
- 2-second delay between retries
- Detailed logging of each attempt

### 3. Structured Logging

- Timestamp for every log entry
- Severity levels (INFO, WARNING, ERROR, SUCCESS)
- Human-readable progress messages
- Machine-parseable format

### 4. Pre-flight Validation

✅ Module availability check  
✅ Storage context creation  
✅ Network connectivity test  
✅ File share existence verification  
✅ Credential validation

### 5. Detailed Statistics

- Total items discovered
- Items successfully deleted
- Protected items preserved
- Failed deletion count
- Total execution duration

### 6. Verification Step

After deletion, the script:
- Re-lists file share contents
- Verifies only protected items remain
- Fails if non-protected items persist
- Provides detailed residual file list

## Testing and Validation

### Manual Testing

#### Test 1: Verify Cleanup with Valid Configuration

```bash
# 1. Populate file share with test files
az storage file upload \
  --share-name ari-data \
  --source ./test-file.txt \
  --account-name mystorageaccount \
  --account-key $STORAGE_KEY

# 2. Trigger ARI job via web interface

# 3. Check logs for cleanup messages
az containerapp logs show \
  --name azure-resource-inventory \
  --resource-group my-rg \
  --follow

# Expected: Should see cleanup logs and successful completion
```

#### Test 2: Verify Protected Folders are Preserved

```bash
# 1. Create protected folder with content
az storage directory create \
  --name .jobs \
  --share-name ari-data \
  --account-name mystorageaccount

az storage file upload \
  --share-name ari-data \
  --source ./job-data.json \
  --path .jobs/job-data.json \
  --account-name mystorageaccount

# 2. Run cleanup

# 3. Verify .jobs folder still exists
az storage file list \
  --share-name ari-data \
  --account-name mystorageaccount

# Expected: .jobs folder and its contents should remain
```

#### Test 3: Verify Cleanup Failure Blocks ARI

```bash
# 1. Configure with invalid storage key
az containerapp update \
  --name azure-resource-inventory \
  --resource-group my-rg \
  --set-env-vars AZURE_STORAGE_KEY=invalid_key

# 2. Trigger ARI job

# 3. Check job status

# Expected: Job should fail with cleanup error message
# Expected: ARI should NOT execute
```

### Automated Testing

Create a test script to validate cleanup behavior:

```bash
#!/bin/bash
# test-cleanup.sh

echo "Testing Azure File Share Cleanup..."

# Test 1: Upload test files
echo "1. Uploading test files..."
az storage file upload --share-name ari-data --source test1.txt --account-name $STORAGE_ACCOUNT
az storage file upload --share-name ari-data --source test2.txt --account-name $STORAGE_ACCOUNT

# Test 2: Create protected folder
echo "2. Creating protected folder..."
az storage directory create --name .jobs --share-name ari-data --account-name $STORAGE_ACCOUNT

# Test 3: Run cleanup script directly
echo "3. Running cleanup script..."
pwsh -File ./powershell/clear-azure-fileshare.ps1 \
  -StorageAccountName $STORAGE_ACCOUNT \
  -StorageAccountKey $STORAGE_KEY \
  -FileShareName ari-data

# Test 4: Verify results
echo "4. Verifying cleanup..."
REMAINING=$(az storage file list --share-name ari-data --account-name $STORAGE_ACCOUNT --query "length(@)")

if [ "$REMAINING" -eq 1 ]; then
  echo "✅ Test passed: Only protected folder remains"
else
  echo "❌ Test failed: Unexpected items remain"
fi
```

## Troubleshooting

### Quick Diagnosis

**Problem**: Cleanup is not running

**Check**:
```bash
# Verify environment variables
az containerapp show \
  --name azure-resource-inventory \
  --resource-group my-rg \
  --query properties.template.containers[0].env
```

**Solution**: Ensure all three variables are set (AZURE_STORAGE_ACCOUNT, AZURE_STORAGE_KEY, AZURE_FILE_SHARE)

---

**Problem**: Cleanup fails with "unauthorized" error

**Check**:
```bash
# Test storage account access
az storage account show \
  --name mystorageaccount \
  --resource-group my-rg
```

**Solution**: 
- Verify storage key is current (not rotated)
- Check storage account firewall rules
- Ensure container has network access to storage account

---

**Problem**: Some files remain after cleanup

**Check**: Review logs for specific deletion failures

**Solution**:
- Check if files are locked by another process
- Verify file names don't match protected patterns
- Consider manual cleanup if persistent

For detailed troubleshooting, see [CLEANUP-TROUBLESHOOTING.md](./CLEANUP-TROUBLESHOOTING.md)

## Advanced Usage

### Manual Cleanup Execution

You can run the cleanup script manually for testing:

```powershell
pwsh -File ./powershell/clear-azure-fileshare.ps1 `
  -StorageAccountName "mystorageaccount" `
  -StorageAccountKey "your-key-here" `
  -FileShareName "ari-data"
```

### Customizing Protected Items

To add custom protected folders, modify the script:

```powershell
# In clear-azure-fileshare.ps1, update the Test-IsProtected function:
$protectedFolders = @(
    '.jobs',
    '.snapshots',
    '$logs',
    'System Volume Information',
    'my-custom-folder'  # Add your custom folder here
)
```

### Integration with CI/CD

Example GitHub Actions workflow:

```yaml
- name: Cleanup Azure File Share
  env:
    AZURE_STORAGE_ACCOUNT: ${{ secrets.STORAGE_ACCOUNT }}
    AZURE_STORAGE_KEY: ${{ secrets.STORAGE_KEY }}
    AZURE_FILE_SHARE: ari-data
  run: |
    pwsh -File ./powershell/clear-azure-fileshare.ps1 \
      -StorageAccountName $AZURE_STORAGE_ACCOUNT \
      -StorageAccountKey $AZURE_STORAGE_KEY \
      -FileShareName $AZURE_FILE_SHARE
```

## Best Practices

### 1. Secure Storage Keys

✅ **DO**:
- Store keys in Azure Key Vault
- Use Container App secrets for keys
- Rotate keys regularly
- Use Managed Identity when possible

❌ **DON'T**:
- Store keys in plain text
- Commit keys to source control
- Share keys via email or chat

### 2. Monitor Cleanup Operations

- Review logs after each cleanup
- Set up alerts for cleanup failures
- Track cleanup duration trends
- Monitor storage capacity

### 3. Test Before Production

- Test cleanup in non-production environment
- Validate protected items are preserved
- Verify failure scenarios block ARI correctly
- Document any custom protected items

### 4. Plan for Failures

- Document manual cleanup procedures
- Have backup of critical job data
- Know how to disable cleanup in emergency
- Maintain contact info for storage admins

### 5. Regular Maintenance

- Review protected folder list quarterly
- Update cleanup script with new system folders
- Test cleanup after Azure Storage updates
- Keep Az.Storage module up to date

### 6. Capacity Planning

- Monitor file share growth
- Set up storage capacity alerts
- Plan for report retention if needed
- Consider archival strategy for historical reports

## Related Documentation

- [CLEANUP-TROUBLESHOOTING.md](./CLEANUP-TROUBLESHOOTING.md) - Detailed troubleshooting guide
- [CONTAINER-DEPLOYMENT.md](../CONTAINER-DEPLOYMENT.md) - Container deployment guide
- [QUICK-SETUP.md](../QUICK-SETUP.md) - Quick setup instructions
- [README.md](../README.md) - Main project documentation

## Support

For issues or questions:
1. Check [CLEANUP-TROUBLESHOOTING.md](./CLEANUP-TROUBLESHOOTING.md)
2. Review container logs for error messages
3. Open an issue on GitHub with logs and error details
4. Include cleanup statistics from failed runs

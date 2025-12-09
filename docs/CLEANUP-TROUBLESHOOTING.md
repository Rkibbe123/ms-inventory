# Azure File Share Cleanup Troubleshooting Guide

## Overview

This guide provides detailed troubleshooting steps for Azure File Share cleanup failures. Use this guide when cleanup prevents ARI execution or behaves unexpectedly.

## Table of Contents

- [Overview](#overview)
- [Common Error Scenarios](#common-error-scenarios)
- [Log Analysis Guide](#log-analysis-guide)
- [Emergency Manual Cleanup](#emergency-manual-cleanup)
- [Integration with Monitoring](#integration-with-monitoring)
- [Preventive Measures](#preventive-measures)
- [Support Escalation](#support-escalation)

## Common Error Scenarios

### Error 1: Authentication Failure

#### Symptoms
```
[ERROR] Failed to create storage context: The remote server returned an error: (403) Forbidden
[ERROR] Please verify storage account name and key are correct
```

#### Root Causes
- Invalid storage account key
- Storage account key has been rotated
- Storage account name is incorrect
- Network policy blocking access

#### Resolution Steps

1. **Verify Storage Account Name**
   ```bash
   # Check if storage account exists
   az storage account show --name mystorageaccount --resource-group my-rg
   ```

2. **Get Current Storage Key**
   ```bash
   # Retrieve primary key
   az storage account keys list \
     --account-name mystorageaccount \
     --resource-group my-rg \
     --query "[0].value" -o tsv
   ```

3. **Update Container App with New Key**
   ```bash
   az containerapp update \
     --name azure-resource-inventory \
     --resource-group my-rg \
     --set-env-vars AZURE_STORAGE_KEY=new-key-here
   ```

4. **Test Access**
   ```bash
   # Test with new key
   az storage share list \
     --account-name mystorageaccount \
     --account-key new-key-here
   ```

#### Prevention
- Set up key rotation reminders
- Use Azure Key Vault for key management
- Consider using Managed Identity instead of keys
- Document key rotation procedures

---

### Error 2: Network Connectivity Issues

#### Symptoms
```
[ERROR] Network connectivity test failed: Unable to connect to the remote server
[ERROR] Please check network connectivity to Azure Storage
```

#### Root Causes
- Storage account firewall rules blocking container IP
- Virtual network configuration issues
- DNS resolution problems
- Azure Storage service outage

#### Resolution Steps

1. **Check Storage Account Firewall**
   ```bash
   # View firewall rules
   az storage account show \
     --name mystorageaccount \
     --resource-group my-rg \
     --query networkRuleSet
   ```

2. **Allow Container App Access**
   ```bash
   # Option 1: Allow all networks (less secure)
   az storage account update \
     --name mystorageaccount \
     --resource-group my-rg \
     --default-action Allow

   # Option 2: Add specific subnet (more secure)
   az storage account network-rule add \
     --account-name mystorageaccount \
     --resource-group my-rg \
     --subnet /subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{vnet}/subnets/{subnet}
   ```

3. **Verify DNS Resolution**
   ```bash
   # From within container, test DNS
   nslookup mystorageaccount.file.core.windows.net
   ```

4. **Check Azure Service Health**
   ```bash
   # Check for Azure Storage service issues
   # Use Azure Portal: https://status.azure.com or Azure Service Health
   az rest --method get \
     --url "https://management.azure.com/subscriptions/{subscription-id}/providers/Microsoft.ResourceHealth/availabilityStatuses?api-version=2023-07-01"
   
   # Alternatively, check storage account health specifically
   az storage account show \
     --name mystorageaccount \
     --resource-group my-rg \
     --query statusOfPrimary
   ```

#### Prevention
- Document network architecture
- Use private endpoints for secure access
- Configure firewall rules before deployment
- Set up Azure Service Health alerts

---

### Error 3: File Share Not Found

#### Symptoms
```
[WARNING] File share 'ari-data' does not exist. Nothing to clean.
[SUCCESS] Cleanup completed (nothing to do)
```

#### Root Causes
- File share was deleted
- File share name is incorrect
- File share is in different storage account
- Permissions prevent listing shares

#### Resolution Steps

1. **List Existing File Shares**
   ```bash
   az storage share list \
     --account-name mystorageaccount \
     --account-key $STORAGE_KEY
   ```

2. **Create Missing File Share**
   ```bash
   az storage share create \
     --name ari-data \
     --account-name mystorageaccount \
     --account-key $STORAGE_KEY \
     --quota 100
   ```

3. **Update Container App Configuration**
   ```bash
   # If file share name is different
   az containerapp update \
     --name azure-resource-inventory \
     --resource-group my-rg \
     --set-env-vars AZURE_FILE_SHARE=correct-share-name
   ```

4. **Verify Volume Mount**
   ```bash
   # Check container app volume configuration
   az containerapp show \
     --name azure-resource-inventory \
     --resource-group my-rg \
     --query properties.template.volumes
   ```

#### Prevention
- Enable soft delete for file shares
- Document file share naming conventions
- Use infrastructure as code (Bicep/Terraform)
- Set up alerts for deleted resources

---

### Error 4: Files Locked by Another Process

#### Symptoms
```
[WARNING] Failed to delete report.xlsx (attempt 1/3): The specified resource is locked. Retrying in 2 seconds...
[WARNING] Failed to delete report.xlsx (attempt 2/3): The specified resource is locked. Retrying in 2 seconds...
[ERROR] Failed to delete report.xlsx after 3 attempts: The specified resource is locked
[ERROR] Items failed to delete: 1
[ERROR] CLEANUP FAILED
```

#### Root Causes
- Multiple container instances accessing same file share
- File opened in another process
- File share mounted in multiple locations
- Azure Files internal lock

#### Resolution Steps

1. **Check Running Container Instances**
   ```bash
   # List all revisions and replicas
   az containerapp revision list \
     --name azure-resource-inventory \
     --resource-group my-rg \
     --query "[].{name:name,replicas:properties.replicas,active:properties.active}"
   ```

2. **Scale Down to Single Instance**
   ```bash
   # Temporarily scale to 1 replica
   az containerapp update \
     --name azure-resource-inventory \
     --resource-group my-rg \
     --min-replicas 1 \
     --max-replicas 1
   ```

3. **Wait and Retry**
   ```bash
   # Wait 30 seconds for locks to clear
   sleep 30
   # Retry cleanup
   ```

4. **Manual Lock Investigation**
   ```bash
   # Check file share leases
   az storage file list \
     --share-name ari-data \
     --account-name mystorageaccount \
     --query "[?properties.lease.status=='locked']"
   ```

#### Prevention
- Ensure single-instance execution during cleanup
- Implement proper file handle cleanup
- Use advisory locks in application code
- Set appropriate lease duration

---

### Error 5: Insufficient Permissions

#### Symptoms
```
[ERROR] Failed to delete directory: AzureResourceInventory (attempt 1/3): Forbidden
[ERROR] Please check storage account permissions
```

#### Root Causes
- Storage account key has limited permissions
- Azure RBAC role missing required permissions
- Storage account access tier restrictions
- Network security group blocking traffic

#### Resolution Steps

1. **Verify Storage Account Permissions**
   ```bash
   # Check your access level
   az role assignment list \
     --scope /subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Storage/storageAccounts/{storage-account}
   ```

2. **Grant Required Permissions (if using Managed Identity)**
   
   **Note**: This script uses storage account keys by default, which have full access. Only follow this step if you're using Managed Identity or SAS tokens instead.
   
   ```bash
   # Assign Storage File Data SMB Share Contributor role (for RBAC auth)
   az role assignment create \
     --role "Storage File Data SMB Share Contributor" \
     --assignee-object-id {object-id} \
     --scope /subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Storage/storageAccounts/{storage-account}
   ```

3. **Test with Storage Key (Recommended)**
   
   Storage account keys provide full access and are the recommended authentication method for cleanup:
   
   ```bash
   # Verify key has full access
   az storage file delete \
     --share-name ari-data \
     --path test.txt \
     --account-name mystorageaccount \
     --account-key $STORAGE_KEY
   ```

#### Prevention
- **Use storage account keys for cleanup operations** (simplest and most reliable)
- Document required permissions if using alternative auth methods
- Use Managed Identity with appropriate roles only for production scenarios
- Regularly audit access permissions

---

### Error 6: Az.Storage Module Not Available

#### Symptoms
```
[ERROR] Failed to import Az.Storage module: The specified module 'Az.Storage' was not loaded
[ERROR] Please ensure Az.Storage module is installed: Install-Module Az.Storage
```

#### Root Causes
- PowerShell module not installed in container image
- Module installation failed during build
- PowerShell module path not configured correctly
- Module version incompatibility

#### Resolution Steps

1. **Check Module Installation in Dockerfile**
   ```dockerfile
   # Add to Dockerfile if missing
   RUN pwsh -Command "Install-Module -Name Az.Storage -Force -AllowClobber -Scope AllUsers"
   ```

2. **Rebuild Container Image**
   ```bash
   # Rebuild and push image
   docker build -t azure-resource-inventory:latest .
   docker push your-registry/azure-resource-inventory:latest
   ```

3. **Verify Module in Running Container**
   ```bash
   # Execute in running container
   az containerapp exec \
     --name azure-resource-inventory \
     --resource-group my-rg \
     --command "pwsh -Command 'Get-Module -ListAvailable Az.Storage'"
   ```

4. **Test Module Import**
   ```bash
   # Test import manually
   az containerapp exec \
     --name azure-resource-inventory \
     --resource-group my-rg \
     --command "pwsh -Command 'Import-Module Az.Storage'"
   ```

#### Prevention
- Verify module installation in Dockerfile
- Pin module versions in Dockerfile
- Test container image before deployment
- Include module verification in CI/CD pipeline

---

### Error 7: Protected Items Incorrectly Deleted

#### Symptoms
```
[ERROR] Protected folder .jobs was not found after cleanup
[ERROR] Job persistence data may have been lost
```

#### Root Causes
- Bug in protected item detection logic
- Case sensitivity issues
- Pattern matching error
- Script modification without testing

#### Resolution Steps

1. **Verify Protected Items Logic**
   ```powershell
   # Check Test-IsProtected function in script
   Test-IsProtected -ItemName ".jobs" -IsDirectory $true
   # Should return: True
   ```

2. **Restore from Backup (if available)**
   ```bash
   # List snapshots
   az storage share snapshot list \
     --share-name ari-data \
     --account-name mystorageaccount

   # Restore from snapshot
   az storage file copy start \
     --source-share ari-data \
     --source-path .jobs/job-data.json \
     --destination-share ari-data \
     --destination-path .jobs/job-data.json \
     --source-snapshot {snapshot-time}
   ```

3. **Review Script Changes**
   ```bash
   # Check recent changes to cleanup script
   git log --oneline -- powershell/clear-azure-fileshare.ps1
   git diff HEAD~1 -- powershell/clear-azure-fileshare.ps1
   ```

4. **Add Additional Protection**
   ```powershell
   # In Test-IsProtected function, add validation
   if ($ItemName -match '^\.jobs$|^\.snapshots$|^\$logs$') {
       return $true
   }
   ```

#### Prevention
- Never modify protected items list without thorough testing
- Add integration tests for protected items
- Use snapshots for critical folders
- Document all protected items in code comments

## Log Analysis Guide

### Understanding Log Levels

| Level | Meaning | Action Required |
|-------|---------|-----------------|
| `[INFO]` | Normal operation | None, informational only |
| `[SUCCESS]` | Operation completed successfully | None, expected behavior |
| `[WARNING]` | Non-critical issue | Monitor, may require investigation |
| `[ERROR]` | Critical failure | Immediate action required |

### Key Log Patterns

#### Successful Cleanup
```
[INFO] Listing contents of file share...
[INFO] Found 15 items in file share
[INFO] Items to delete: 14
[SUCCESS] Successfully deleted: report.xlsx
...
[SUCCESS] All non-protected items were successfully deleted
[SUCCESS] CLEANUP COMPLETED SUCCESSFULLY
```

#### Authentication Failure
```
[INFO] Creating storage context...
[ERROR] Failed to create storage context: The remote server returned an error: (403) Forbidden
```
**Action**: Check storage account credentials

#### Network Issues
```
[INFO] Testing network connectivity to storage account...
[ERROR] Network connectivity test failed: Unable to connect to the remote server
```
**Action**: Check firewall rules and network configuration

#### Partial Cleanup Failure
```
[SUCCESS] Successfully deleted: file1.xlsx
[WARNING] Failed to delete file2.xlsx (attempt 1/3): The specified resource is locked
[WARNING] Failed to delete file2.xlsx (attempt 2/3): The specified resource is locked
[ERROR] Failed to delete file2.xlsx after 3 attempts: The specified resource is locked
[ERROR] Items failed to delete: 1
[ERROR] CLEANUP FAILED
```
**Action**: Investigate locked files, check for concurrent access

### Log Collection Commands

```bash
# View recent container logs
az containerapp logs show \
  --name azure-resource-inventory \
  --resource-group my-rg \
  --tail 100

# Follow logs in real-time
az containerapp logs show \
  --name azure-resource-inventory \
  --resource-group my-rg \
  --follow

# Export logs to file
az monitor log-analytics query \
  --workspace {workspace-id} \
  --analytics-query "ContainerAppConsoleLogs_CL | where ContainerName_s == 'azure-resource-inventory' | order by TimeGenerated desc" \
  --output table > cleanup-logs.txt
```

## Emergency Manual Cleanup

### When to Use Manual Cleanup

Use manual cleanup when:
- Automatic cleanup repeatedly fails
- File share is critically full
- Immediate cleanup is required
- Testing cleanup behavior

### Manual Cleanup via Azure CLI

```bash
#!/bin/bash
# emergency-cleanup.sh

STORAGE_ACCOUNT="mystorageaccount"
STORAGE_KEY="your-key-here"
FILE_SHARE="ari-data"

echo "Emergency manual cleanup starting..."

# List all files
FILES=$(az storage file list \
  --share-name $FILE_SHARE \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY \
  --output tsv \
  --query "[].name")

# Delete each file except protected items
for file in $FILES; do
  case $file in
    .jobs|.snapshots|\$logs|"System Volume Information")
      echo "Skipping protected: $file"
      ;;
    *)
      echo "Deleting: $file"
      az storage file delete \
        --share-name $FILE_SHARE \
        --path "$file" \
        --account-name $STORAGE_ACCOUNT \
        --account-key $STORAGE_KEY
      ;;
  esac
done

echo "Emergency cleanup completed"
```

### Manual Cleanup via Azure Portal

1. Navigate to **Storage Account** → **File shares**
2. Click on file share name (e.g., `ari-data`)
3. **IMPORTANT**: Do NOT delete these folders:
   - `.jobs`
   - `.snapshots`
   - `$logs`
   - `System Volume Information`
4. Select non-protected files and directories
5. Click **Delete**
6. Confirm deletion

### Manual Cleanup via Storage Explorer

1. Open **Azure Storage Explorer**
2. Connect to your storage account
3. Navigate to **File Shares** → **ari-data**
4. Select items to delete (avoid protected folders)
5. Right-click → **Delete**
6. Confirm deletion

### Verification After Manual Cleanup

```bash
# Verify only protected items remain
az storage file list \
  --share-name ari-data \
  --account-name mystorageaccount \
  --account-key $STORAGE_KEY \
  --query "[].{Name:name, Type:properties.resourceType}"
```

Expected output:
```json
[
  {
    "Name": ".jobs",
    "Type": "Directory"
  }
]
```

## Integration with Monitoring

### Azure Monitor Alerts

#### Alert 1: Cleanup Failure Alert

```json
{
  "properties": {
    "description": "Alert when file share cleanup fails",
    "severity": 2,
    "enabled": true,
    "evaluationFrequency": "PT5M",
    "windowSize": "PT5M",
    "criteria": {
      "allOf": [
        {
          "query": "ContainerAppConsoleLogs_CL | where Log_s contains 'CLEANUP FAILED'",
          "timeAggregation": "Count",
          "operator": "GreaterThan",
          "threshold": 0
        }
      ]
    },
    "actions": {
      "actionGroups": [
        "/subscriptions/{sub}/resourceGroups/{rg}/providers/microsoft.insights/actionGroups/ops-team"
      ]
    }
  }
}
```

#### Alert 2: Cleanup Duration Alert

```json
{
  "properties": {
    "description": "Alert when cleanup takes too long",
    "severity": 3,
    "enabled": true,
    "criteria": {
      "allOf": [
        {
          "query": "ContainerAppConsoleLogs_CL | where Log_s contains 'Duration:' | extend duration=todouble(extract('Duration: ([0-9.]+)', 1, Log_s)) | where duration > 120",
          "timeAggregation": "Count",
          "operator": "GreaterThan",
          "threshold": 0
        }
      ]
    }
  }
}
```

### Log Analytics Queries

#### Query 1: Cleanup Success Rate

```kusto
ContainerAppConsoleLogs_CL
| where ContainerName_s == "azure-resource-inventory"
| where Log_s contains "CLEANUP"
| summarize 
    Total = count(),
    Success = countif(Log_s contains "CLEANUP COMPLETED SUCCESSFULLY"),
    Failed = countif(Log_s contains "CLEANUP FAILED")
| extend SuccessRate = (Success * 100.0) / Total
```

#### Query 2: Average Cleanup Duration

```kusto
ContainerAppConsoleLogs_CL
| where Log_s contains "Duration:"
| extend duration = todouble(extract("Duration: ([0-9.]+)", 1, Log_s))
| summarize 
    AvgDuration = avg(duration),
    MaxDuration = max(duration),
    MinDuration = min(duration)
    by bin(TimeGenerated, 1d)
```

#### Query 3: Protected Items Count Trend

```kusto
ContainerAppConsoleLogs_CL
| where Log_s contains "Protected items preserved:"
| extend protected = toint(extract("Protected items preserved: ([0-9]+)", 1, Log_s))
| summarize AvgProtected = avg(protected) by bin(TimeGenerated, 1d)
```

### Dashboards

Create Azure Dashboard with these tiles:
1. **Cleanup Success Rate** (last 7 days)
2. **Average Cleanup Duration** (trend)
3. **Failed Cleanup Count** (last 24 hours)
4. **Total Items Deleted** (trend)
5. **Protected Items Count** (current)

## Preventive Measures

### 1. Regular Testing

```bash
# Weekly cleanup test script
#!/bin/bash
# test-cleanup-weekly.sh

echo "Weekly cleanup test - $(date)"

# Upload test files
for i in {1..5}; do
  echo "Test content $i" > test-file-$i.txt
  az storage file upload \
    --share-name ari-data \
    --source test-file-$i.txt \
    --account-name $STORAGE_ACCOUNT
done

# Trigger cleanup via API
curl -X POST https://your-app.azurewebsites.net/trigger-cleanup

# Verify results
REMAINING=$(az storage file list --share-name ari-data --account-name $STORAGE_ACCOUNT --query "length([?name!='jobs'])")

if [ "$REMAINING" -eq 0 ]; then
  echo "✅ Weekly test passed"
else
  echo "❌ Weekly test failed - $REMAINING files remain"
fi
```

### 2. Snapshot Management

```bash
# Create daily snapshot before cleanup
az storage share snapshot \
  --name ari-data \
  --account-name mystorageaccount \
  --metadata "backup_type=pre_cleanup,date=$(date +%Y%m%d)"

# Clean up old snapshots (keep last 7 days)
az storage share snapshot list \
  --share-name ari-data \
  --account-name mystorageaccount \
  --query "[?metadata.backup_type=='pre_cleanup' && snapshot < '$(date -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)'].snapshot" \
  -o tsv | while read snapshot; do
    az storage share snapshot delete \
      --name ari-data \
      --snapshot "$snapshot" \
      --account-name mystorageaccount
  done
```

### 3. Health Checks

```bash
# Daily health check script
#!/bin/bash
# health-check.sh

echo "Cleanup health check - $(date)"

# Check 1: Environment variables configured
VARS_OK=true
for var in AZURE_STORAGE_ACCOUNT AZURE_STORAGE_KEY AZURE_FILE_SHARE; do
  if [ -z "${!var}" ]; then
    echo "❌ $var not configured"
    VARS_OK=false
  fi
done

# Check 2: Storage account accessible
if ! az storage account show --name $AZURE_STORAGE_ACCOUNT &>/dev/null; then
  echo "❌ Storage account not accessible"
  exit 1
fi

# Check 3: File share exists
if ! az storage share show --name $AZURE_FILE_SHARE --account-name $AZURE_STORAGE_ACCOUNT &>/dev/null; then
  echo "❌ File share does not exist"
  exit 1
fi

# Check 4: Protected folders exist
if ! az storage directory exists --name .jobs --share-name $AZURE_FILE_SHARE --account-name $AZURE_STORAGE_ACCOUNT &>/dev/null; then
  echo "⚠️ Protected folder .jobs does not exist"
fi

echo "✅ Health check passed"
```

### 4. Documentation Updates

- Review this guide quarterly
- Update after each Azure Storage service change
- Document all custom protected items
- Keep troubleshooting steps current

## Support Escalation

### Level 1: Self-Service

1. Review this troubleshooting guide
2. Check container logs
3. Verify configuration
4. Try manual cleanup

### Level 2: Team Support

If issues persist after Level 1:

**Provide**:
- Container logs (last 1000 lines)
- Error messages
- Environment configuration (sanitized)
- Steps to reproduce
- Timeline of events

**Contact**: Your DevOps or Platform team

### Level 3: Azure Support

If issues are Azure-related:

**Prepare**:
- Azure support request with severity based on impact
- Subscription ID
- Resource IDs (storage account, container app)
- Complete error logs
- Network diagrams

**Azure Support Categories**:
- **Storage**: For file share issues
- **Container Apps**: For container execution issues
- **Networking**: For connectivity issues

### Useful Information to Collect

```bash
# Collect diagnostic information
#!/bin/bash
# collect-diagnostics.sh

echo "=== Diagnostic Information ===" > diagnostics.txt
echo "Timestamp: $(date)" >> diagnostics.txt
echo "" >> diagnostics.txt

echo "=== Environment Variables ===" >> diagnostics.txt
az containerapp show \
  --name azure-resource-inventory \
  --resource-group my-rg \
  --query properties.template.containers[0].env \
  >> diagnostics.txt

echo "" >> diagnostics.txt
echo "=== Recent Logs ===" >> diagnostics.txt
az containerapp logs show \
  --name azure-resource-inventory \
  --resource-group my-rg \
  --tail 500 \
  >> diagnostics.txt

echo "" >> diagnostics.txt
echo "=== Storage Account Status ===" >> diagnostics.txt
az storage account show \
  --name $STORAGE_ACCOUNT \
  --resource-group my-rg \
  >> diagnostics.txt

echo "" >> diagnostics.txt
echo "=== File Share Contents ===" >> diagnostics.txt
az storage file list \
  --share-name ari-data \
  --account-name $STORAGE_ACCOUNT \
  --output table \
  >> diagnostics.txt

echo "Diagnostics collected in diagnostics.txt"
```

## Additional Resources

- [Azure File Share Cleanup Guide](./AZURE-FILESHARE-CLEANUP.md)
- [Azure Storage Documentation](https://docs.microsoft.com/azure/storage/)
- [Azure Container Apps Documentation](https://docs.microsoft.com/azure/container-apps/)
- [PowerShell Az.Storage Module](https://docs.microsoft.com/powershell/module/az.storage/)

## Feedback

If you discover new issues or solutions:
1. Document the issue and resolution
2. Update this guide via pull request
3. Share with the team
4. Consider if monitoring should be added

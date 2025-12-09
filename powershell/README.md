# PowerShell Scripts

This directory contains utility PowerShell scripts for Azure Resource Inventory containerized deployments.

## Scripts

### clear-azure-fileshare.ps1

Clears all files and directories from an Azure Storage File Share before each ARI execution.

**Purpose:**
- Runs before each ARI execution to ensure a clean state
- Prevents accumulation of old reports and diagrams
- Ensures consistent storage usage
- Protects system folders (`.jobs`) from deletion

**Usage:**

```powershell
./clear-azure-fileshare.ps1 `
    -StorageAccountName "mystorageaccount" `
    -StorageAccountKey "abc123..." `
    -FileShareName "ari-data"
```

**Parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| StorageAccountName | Yes | Azure Storage Account name |
| StorageAccountKey | Yes | Storage Account access key |
| FileShareName | Yes | File Share name to clean |

**Protected Folders:**

The following folders are automatically excluded from cleanup:
- `.jobs` - Job persistence directory used by the Flask application

**Note:** If you need to manually delete protected folders (e.g., for troubleshooting or reset scenarios), you can either:
1. Use the Azure Portal to manually delete the folder from the file share
2. Use Azure CLI: `az storage directory delete --name .jobs --share-name ari-data --account-name mystorageaccount --account-key $key`
3. Temporarily modify the script to remove the folder from the `$protectedFolders` array (not recommended for production)

**Exit Codes:**

- `0` - Success (cleanup completed)
- `1` - Error (cleanup failed)

**Features:**

1. **Recursive Deletion**: Deletes all files and subdirectories in the file share root
2. **Protected Folders**: Automatically excludes system folders from deletion
3. **Verification**: Lists remaining files after cleanup to verify success
4. **Detailed Logging**: Provides progress updates and summary statistics
5. **Error Handling**: Reports individual file deletion failures without stopping

**Example Output:**

```
🧹 Azure File Share Cleanup
=======================================
Storage Account: mystorageaccount
File Share: ari-data

Connecting to Azure Storage...
✅ Connected to storage account successfully

Checking if file share exists...
✅ File share found

Listing contents of file share...
Found 15 items in file share
🔒 Protected folder will be preserved: .jobs
Items to delete: 14
Protected items: 1

Deleting file: report.xlsx
Deleting directory: diagrams
...

=======================================
✅ Cleanup completed!
   Items deleted: 14
   Protected items preserved: 1
=======================================

🔍 Verifying cleanup...
Listing remaining files in file share...
📁 Remaining items in file share: 1
   - .jobs (Directory) [PROTECTED]
✅ All non-protected items were successfully deleted

=======================================
```

**Integration:**

This script is automatically called by the Flask application when the following environment variables are set:

- `AZURE_STORAGE_ACCOUNT`
- `AZURE_STORAGE_KEY`
- `AZURE_FILE_SHARE`

The cleanup runs **before every ARI execution** to ensure a clean starting state.

**Troubleshooting:**

If cleanup fails:

1. **Verify Storage Account Access**: Check that the storage account name and key are correct
2. **Check File Share Existence**: Ensure the file share exists and is accessible
3. **Review Permissions**: Verify the storage account key has sufficient permissions
4. **Check Network Connectivity**: Ensure the container can reach Azure Storage
5. **Review Logs**: Check the container logs for detailed error messages

Common issues:

- **"File share does not exist"**: Create the file share or check the name
- **"Failed to connect"**: Verify storage account credentials
- **"Failed to delete"**: Check if files are locked or in use
- **"Too many items failed"**: May indicate permission or network issues

See [Container Deployment Guide](../CONTAINER-DEPLOYMENT.md) for more details.

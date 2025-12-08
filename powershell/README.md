# PowerShell Scripts

This directory contains utility PowerShell scripts for Azure Resource Inventory containerized deployments.

## Scripts

### clear-azure-fileshare.ps1

Clears all files and directories from an Azure Storage File Share.

**Purpose:**
- Runs before each ARI execution to ensure a clean state
- Prevents accumulation of old reports and diagrams
- Ensures consistent storage usage

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

**Exit Codes:**

- `0` - Success (cleanup completed)
- `1` - Error (cleanup failed)

**Integration:**

This script is automatically called by the Flask application when the following environment variables are set:

- `AZURE_STORAGE_ACCOUNT`
- `AZURE_STORAGE_KEY`
- `AZURE_FILE_SHARE`

See [Container Deployment Guide](../CONTAINER-DEPLOYMENT.md) for more details.

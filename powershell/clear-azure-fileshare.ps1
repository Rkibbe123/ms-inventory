#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Clears all files and directories from an Azure Storage File Share.

.DESCRIPTION
    This script deletes all files and folders from a specified Azure File Share,
    except for protected system folders and files (e.g., .jobs, .snapshots).
    It is intended to run before Azure Resource Inventory (ARI) execution to ensure
    a clean state for report generation while preserving job persistence data.
    
    Features:
    - Comprehensive system folder protection
    - Retry logic for transient failures
    - Structured logging with timestamps
    - Pre-flight validation
    - Detailed progress reporting
    - Cleanup statistics tracking

.PARAMETER StorageAccountName
    The name of the Azure Storage Account.

.PARAMETER StorageAccountKey
    The access key for the Azure Storage Account.

.PARAMETER FileShareName
    The name of the Azure File Share to clear.

.EXAMPLE
    ./clear-azure-fileshare.ps1 -StorageAccountName "mystorageacct" -StorageAccountKey "abc123..." -FileShareName "ari-data"
    
.NOTES
    Protected folders that will not be deleted:
    - .jobs (job persistence directory)
    - .snapshots (Azure Files snapshot directory)
    - $logs (Azure Storage logs directory)
    - System Volume Information (Windows system folder)
    
    Protected file patterns:
    - *.lock (lock files)
    - *.tmp (temporary files that may be in use)
    - .gitkeep (placeholder files for empty directories)
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountKey,
    
    [Parameter(Mandatory=$true)]
    [string]$FileShareName
)

$ErrorActionPreference = 'Stop'

# Global statistics
$script:StartTime = Get-Date
$script:TotalItems = 0
$script:DeletedCount = 0
$script:FailedCount = 0
$script:ProtectedCount = 0

# Configuration
# NOTE: These could be made configurable via script parameters or environment variables
# if operators need to adjust retry behavior based on their network conditions.
# For now, using sensible defaults that work for most scenarios.
$MaxRetries = 3
$RetryDelaySeconds = 2

# Logging function with timestamps and severity levels
function Write-Log {
    <#
    .SYNOPSIS
        Writes a log message with timestamp and severity level.
    
    .PARAMETER Message
        The message to log.
    
    .PARAMETER Level
        The severity level (INFO, WARNING, ERROR, SUCCESS).
    
    .PARAMETER NoNewline
        If specified, does not add a newline after the message.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO',
        
        [Parameter(Mandatory=$false)]
        [switch]$NoNewline
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colorMap = @{
        'INFO'    = 'White'
        'WARNING' = 'Yellow'
        'ERROR'   = 'Red'
        'SUCCESS' = 'Green'
    }
    
    $color = $colorMap[$Level]
    $formattedMessage = "[$timestamp] [$Level] $Message"
    
    if ($NoNewline) {
        Write-Host $formattedMessage -ForegroundColor $color -NoNewline
    } else {
        Write-Host $formattedMessage -ForegroundColor $color
    }
}

# Helper function to check if an item is a directory
function Test-IsDirectory {
    <#
    .SYNOPSIS
        Determines if an Azure Storage File item is a directory.
    
    .DESCRIPTION
        Checks if an Azure Storage File item is a directory by examining its
        IsDirectory property or type. Supports both property-based and type-based detection.
    
    .PARAMETER item
        The Azure Storage File item to check.
    
    .OUTPUTS
        System.Boolean
        Returns $true if the item is a directory, $false otherwise.
    #>
    param($item)
    
    # Check if it's a directory using IsDirectory property or CloudFileDirectory type
    return (
        ($item.PSObject.Properties.Name -contains 'IsDirectory' -and $item.IsDirectory) -or 
        ($item -is [Microsoft.Azure.Storage.File.CloudFileDirectory])
    )
}

# Helper function to check if an item should be protected
function Test-IsProtected {
    <#
    .SYNOPSIS
        Determines if a file or folder should be protected from deletion.
    
    .PARAMETER ItemName
        The name of the item to check.
    
    .PARAMETER IsDirectory
        Whether the item is a directory.
    
    .OUTPUTS
        System.Boolean
        Returns $true if the item should be protected, $false otherwise.
    #>
    param(
        [string]$ItemName,
        [bool]$IsDirectory
    )
    
    # Protected folders - never delete these system directories
    $protectedFolders = @(
        '.jobs',                    # Job persistence directory
        '.snapshots',               # Azure Files snapshot directory
        '$logs',                    # Azure Storage logs directory
        'System Volume Information' # Windows system folder
    )
    
    # Protected file patterns - never delete files matching these patterns
    $protectedPatterns = @(
        '*.lock',   # Lock files
        '*.tmp',    # Temporary files that may be in use
        '.gitkeep'  # Placeholder files for empty directories
    )
    
    # Check if it's a protected folder
    if ($IsDirectory -and $protectedFolders -contains $ItemName) {
        return $true
    }
    
    # Check if it matches a protected file pattern
    if (-not $IsDirectory) {
        foreach ($pattern in $protectedPatterns) {
            if ($ItemName -like $pattern) {
                return $true
            }
        }
    }
    
    return $false
}

# Function to delete an item with retry logic
function Remove-ItemWithRetry {
    <#
    .SYNOPSIS
        Removes an item from Azure File Share with retry logic.
    
    .PARAMETER ShareName
        The name of the file share.
    
    .PARAMETER Path
        The path to the item.
    
    .PARAMETER Context
        The storage context.
    
    .PARAMETER IsDirectory
        Whether the item is a directory.
    
    .PARAMETER ItemName
        The display name of the item for logging.
    
    .OUTPUTS
        System.Boolean
        Returns $true if deletion succeeded, $false otherwise.
    #>
    param(
        [string]$ShareName,
        [string]$Path,
        [object]$Context,
        [bool]$IsDirectory,
        [string]$ItemName
    )
    
    $attempt = 0
    $success = $false
    
    while ($attempt -lt $script:MaxRetries -and -not $success) {
        $attempt++
        
        try {
            if ($IsDirectory) {
                Write-Log "Deleting directory: $ItemName (attempt $attempt/$script:MaxRetries)" -Level INFO
                Remove-AzStorageDirectory -ShareName $ShareName -Path $Path -Context $Context -Force -ErrorAction Stop
            } else {
                Write-Log "Deleting file: $ItemName (attempt $attempt/$script:MaxRetries)" -Level INFO
                Remove-AzStorageFile -ShareName $ShareName -Path $Path -Context $Context -ErrorAction Stop
            }
            
            $success = $true
            $script:DeletedCount++
            return $true
            
        } catch {
            if ($attempt -lt $script:MaxRetries) {
                Write-Log "Failed to delete $ItemName (attempt $attempt/$script:MaxRetries): $($_.Exception.Message). Retrying in $script:RetryDelaySeconds seconds..." -Level WARNING
                Start-Sleep -Seconds $script:RetryDelaySeconds
            } else {
                Write-Log "Failed to delete $ItemName after $script:MaxRetries attempts: $($_.Exception.Message)" -Level ERROR
                $script:FailedCount++
                return $false
            }
        }
    }
    
    return $false
}

Write-Host "🧹 Azure File Share Cleanup" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "Storage Account: $StorageAccountName" -ForegroundColor Yellow
Write-Host "File Share: $FileShareName" -ForegroundColor Yellow
Write-Host ""

try {
    # Pre-flight validation: Import module
    Write-Log "Importing Az.Storage module..." -Level INFO
    
    try {
        Import-Module Az.Storage -ErrorAction Stop
        Write-Log "Az.Storage module loaded successfully" -Level SUCCESS
    } catch {
        Write-Log "Failed to import Az.Storage module: $($_.Exception.Message)" -Level ERROR
        Write-Log "Please ensure Az.Storage module is installed: Install-Module Az.Storage" -Level ERROR
        exit 1
    }
    
    # Pre-flight validation: Create storage context
    Write-Log "Creating storage context..." -Level INFO
    
    try {
        $context = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey -ErrorAction Stop
        Write-Log "Storage context created successfully" -Level SUCCESS
    } catch {
        Write-Log "Failed to create storage context: $($_.Exception.Message)" -Level ERROR
        Write-Log "Please verify storage account name and key are correct" -Level ERROR
        exit 1
    }
    
    # Pre-flight validation: Test network connectivity
    Write-Log "Testing network connectivity to storage account..." -Level INFO
    
    try {
        # Try to get storage account properties as a connectivity test
        $null = Get-AzStorageShare -Name $FileShareName -Context $context -ErrorAction Stop
        Write-Log "Network connectivity verified" -Level SUCCESS
    } catch {
        Write-Log "Network connectivity test failed: $($_.Exception.Message)" -Level ERROR
        Write-Log "Please check network connectivity to Azure Storage" -Level ERROR
        exit 1
    }
    
    # Pre-flight validation: Check if file share exists
    Write-Log "Verifying file share exists and is accessible..." -Level INFO
    $fileShare = Get-AzStorageShare -Name $FileShareName -Context $context -ErrorAction SilentlyContinue
    
    if (-not $fileShare) {
        Write-Log "File share '$FileShareName' does not exist. Nothing to clean." -Level WARNING
        Write-Log "Cleanup completed (nothing to do)" -Level SUCCESS
        exit 0
    }
    
    Write-Log "File share found and accessible" -Level SUCCESS
    
    # Get all files and directories in the root of the file share
    Write-Log "Listing contents of file share..." -Level INFO
    $items = Get-AzStorageFile -ShareName $FileShareName -Context $context -ErrorAction Stop
    
    $script:TotalItems = $items.Count
    
    if ($items.Count -eq 0) {
        Write-Log "File share is already empty. Nothing to delete." -Level SUCCESS
        
        # Display final statistics
        $duration = (Get-Date) - $script:StartTime
        Write-Host ""
        Write-Host "=======================================" -ForegroundColor Cyan
        Write-Log "Cleanup Statistics:" -Level INFO
        Write-Log "  Total items found: 0" -Level INFO
        Write-Log "  Duration: $($duration.TotalSeconds.ToString('F2')) seconds" -Level INFO
        Write-Host "=======================================" -ForegroundColor Cyan
        
        exit 0
    }
    
    Write-Log "Found $($items.Count) items in file share" -Level INFO
    
    # Filter out protected folders and files
    $itemsToDelete = @()
    $protectedItems = @()
    
    foreach ($item in $items) {
        $itemName = $item.Name
        $isDirectory = Test-IsDirectory $item
        
        if (Test-IsProtected -ItemName $itemName -IsDirectory $isDirectory) {
            $protectedItems += $itemName
            $itemType = if ($isDirectory) { "folder" } else { "file" }
            Write-Log "Protected $itemType will be preserved: $itemName" -Level INFO
            $script:ProtectedCount++
        } else {
            $itemsToDelete += $item
        }
    }
    
    if ($itemsToDelete.Count -eq 0) {
        Write-Log "No items to delete (only protected items present). File share is clean." -Level SUCCESS
        
        # Display final statistics
        $duration = (Get-Date) - $script:StartTime
        Write-Host ""
        Write-Host "=======================================" -ForegroundColor Cyan
        Write-Log "Cleanup Statistics:" -Level INFO
        Write-Log "  Total items found: $script:TotalItems" -Level INFO
        Write-Log "  Protected items preserved: $script:ProtectedCount" -Level INFO
        Write-Log "  Items to delete: 0" -Level INFO
        Write-Log "  Duration: $($duration.TotalSeconds.ToString('F2')) seconds" -Level INFO
        Write-Host "=======================================" -ForegroundColor Cyan
        
        exit 0
    }
    
    Write-Log "Items to delete: $($itemsToDelete.Count)" -Level INFO
    if ($protectedItems.Count -gt 0) {
        Write-Log "Protected items: $($protectedItems.Count)" -Level INFO
    }
    Write-Host ""
    
    # Delete each item (files and directories) with retry logic
    $itemNumber = 0
    foreach ($item in $itemsToDelete) {
        $itemNumber++
        $itemName = $item.Name
        $isDirectory = Test-IsDirectory $item
        $itemType = if ($isDirectory) { "directory" } else { "file" }
        
        Write-Log "Processing item $itemNumber/$($itemsToDelete.Count): $itemName ($itemType)" -Level INFO
        
        $success = Remove-ItemWithRetry `
            -ShareName $FileShareName `
            -Path $itemName `
            -Context $context `
            -IsDirectory $isDirectory `
            -ItemName $itemName
        
        if ($success) {
            Write-Log "Successfully deleted: $itemName" -Level SUCCESS
        }
    }
    
    # Verification: List remaining files to ensure cleanup was successful
    Write-Host ""
    Write-Log "Verifying cleanup..." -Level INFO
    
    try {
        $remainingItems = Get-AzStorageFile -ShareName $FileShareName -Context $context -ErrorAction Stop
        
        if ($remainingItems.Count -eq 0) {
            Write-Log "File share is now completely empty" -Level SUCCESS
        } else {
            Write-Log "Remaining items in file share: $($remainingItems.Count)" -Level INFO
            foreach ($item in $remainingItems) {
                $isDirectory = Test-IsDirectory $item
                $itemType = if ($isDirectory) { "Directory" } else { "File" }
                $isProtected = Test-IsProtected -ItemName $item.Name -IsDirectory $isDirectory
                $protectedMarker = if ($isProtected) { " [PROTECTED]" } else { "" }
                Write-Log "  - $($item.Name) ($itemType)$protectedMarker" -Level INFO
            }
            
            # Check if only protected items remain
            $unprotectedRemaining = @()
            foreach ($item in $remainingItems) {
                $isDirectory = Test-IsDirectory $item
                if (-not (Test-IsProtected -ItemName $item.Name -IsDirectory $isDirectory)) {
                    $unprotectedRemaining += $item
                }
            }
            
            if ($unprotectedRemaining.Count -eq 0) {
                Write-Log "All non-protected items were successfully deleted" -Level SUCCESS
            } else {
                Write-Log "Warning: $($unprotectedRemaining.Count) non-protected item(s) still remain" -Level WARNING
                Write-Log "These items may have failed to delete or were added during cleanup" -Level WARNING
                
                # List the items that remain
                foreach ($item in $unprotectedRemaining) {
                    $isDirectory = Test-IsDirectory $item
                    $itemType = if ($isDirectory) { "Directory" } else { "File" }
                    Write-Log "  - $($item.Name) ($itemType)" -Level WARNING
                }
                
                # Unprotected items remaining is a failure condition
                Write-Host ""
                Write-Log "CLEANUP VERIFICATION FAILED" -Level ERROR
                Write-Log "Unprotected items remain in the file share after cleanup" -Level ERROR
                Write-Log "This indicates incomplete cleanup and may cause issues with ARI" -Level ERROR
                $script:FailedCount += $unprotectedRemaining.Count
            }
        }
    } catch {
        Write-Log "Could not verify cleanup: $($_.Exception.Message)" -Level WARNING
        Write-Log "Cleanup may have succeeded, but verification failed" -Level WARNING
    }
    
    # Calculate duration and display final statistics
    $duration = (Get-Date) - $script:StartTime
    
    Write-Host ""
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Log "Cleanup Statistics:" -Level INFO
    Write-Log "  Total items found: $script:TotalItems" -Level INFO
    Write-Log "  Items deleted: $script:DeletedCount" -Level SUCCESS
    Write-Log "  Protected items preserved: $script:ProtectedCount" -Level INFO
    Write-Log "  Items failed: $script:FailedCount" -Level $(if ($script:FailedCount -gt 0) { 'ERROR' } else { 'INFO' })
    Write-Log "  Duration: $($duration.TotalSeconds.ToString('F2')) seconds" -Level INFO
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Exit with strict success criteria
    # Success only if:
    # 1. No items failed to delete, AND
    # 2. No unprotected items remain after verification
    if ($script:FailedCount -eq 0) {
        Write-Log "CLEANUP COMPLETED SUCCESSFULLY" -Level SUCCESS
        Write-Log "File share is clean and ready for ARI execution" -Level SUCCESS
        exit 0
    } else {
        Write-Log "CLEANUP FAILED" -Level ERROR
        Write-Log "Items successfully deleted: $script:DeletedCount" -Level WARNING
        Write-Log "Items failed to delete: $script:FailedCount" -Level ERROR
        Write-Host ""
        Write-Log "The file share is NOT clean and may contain old files" -Level ERROR
        Write-Log "ARI execution should be blocked to prevent issues" -Level ERROR
        
        Write-Host ""
        Write-Log "Troubleshooting steps:" -Level INFO
        Write-Log "  1. Check if files are locked by another process" -Level INFO
        Write-Log "  2. Verify storage account permissions" -Level INFO
        Write-Log "  3. Review error messages above for specific failures" -Level INFO
        Write-Log "  4. Consider manual cleanup if issues persist" -Level INFO
        
        exit 1
    }
    
} catch {
    Write-Host ""
    Write-Log "ERROR: Failed to clear file share" -Level ERROR
    Write-Log "Error details: $($_.Exception.Message)" -Level ERROR
    Write-Host ""
    
    # Print stack trace for debugging
    Write-Log "Stack trace:" -Level ERROR
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    
    Write-Host ""
    Write-Log "Troubleshooting steps:" -Level INFO
    Write-Log "  1. Verify storage account name and key are correct" -Level INFO
    Write-Log "  2. Check network connectivity to Azure Storage" -Level INFO
    Write-Log "  3. Ensure file share exists and is accessible" -Level INFO
    Write-Log "  4. Verify Az.Storage module is installed and up to date" -Level INFO
    Write-Log "  5. Check Azure Storage firewall and network rules" -Level INFO
    
    exit 1
}

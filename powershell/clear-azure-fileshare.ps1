#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Clears all files and directories from an Azure Storage File Share.

.DESCRIPTION
    This script deletes all files and folders from a specified Azure File Share,
    except for protected system folders (e.g., .jobs).
    It is intended to run before Azure Resource Inventory (ARI) execution to ensure
    a clean state for report generation while preserving job persistence data.

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

Write-Host "🧹 Azure File Share Cleanup" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "Storage Account: $StorageAccountName" -ForegroundColor Yellow
Write-Host "File Share: $FileShareName" -ForegroundColor Yellow
Write-Host ""

try {
    # Create storage context
    Write-Host "Connecting to Azure Storage..." -ForegroundColor Green
    
    # Import the Az.Storage module if not already loaded
    Import-Module Az.Storage -ErrorAction Stop
    
    # Create storage context using account name and key
    $context = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey -ErrorAction Stop
    Write-Host "✅ Connected to storage account successfully" -ForegroundColor Green
    
    # Check if file share exists
    Write-Host ""
    Write-Host "Checking if file share exists..." -ForegroundColor Green
    $fileShare = Get-AzStorageShare -Name $FileShareName -Context $context -ErrorAction SilentlyContinue
    
    if (-not $fileShare) {
        Write-Host "⚠️  File share '$FileShareName' does not exist. Nothing to clean." -ForegroundColor Yellow
        exit 0
    }
    
    Write-Host "✅ File share found" -ForegroundColor Green
    
    # Get all files and directories in the root of the file share
    Write-Host ""
    Write-Host "Listing contents of file share..." -ForegroundColor Green
    $items = Get-AzStorageFile -ShareName $FileShareName -Context $context -ErrorAction Stop
    
    # Protected folders that should not be deleted
    $protectedFolders = @('.jobs')
    
    if ($items.Count -eq 0) {
        Write-Host "✅ File share is already empty. Nothing to delete." -ForegroundColor Green
        exit 0
    }
    
    Write-Host "Found $($items.Count) items in file share" -ForegroundColor Yellow
    
    # Filter out protected folders
    $itemsToDelete = @()
    $protectedItems = @()
    
    foreach ($item in $items) {
        $itemName = $item.Name
        if ($protectedFolders -contains $itemName) {
            $protectedItems += $itemName
            Write-Host "🔒 Protected folder will be preserved: $itemName" -ForegroundColor Cyan
        } else {
            $itemsToDelete += $item
        }
    }
    
    if ($itemsToDelete.Count -eq 0) {
        Write-Host "✅ No items to delete (only protected folders present). File share is clean." -ForegroundColor Green
        exit 0
    }
    
    Write-Host "Items to delete: $($itemsToDelete.Count)" -ForegroundColor Yellow
    if ($protectedItems.Count -gt 0) {
        Write-Host "Protected items: $($protectedItems.Count)" -ForegroundColor Cyan
    }
    
    # Delete each item (files and directories)
    $deletedCount = 0
    $failedCount = 0
    
    foreach ($item in $itemsToDelete) {
        try {
            $itemName = $item.Name
            
            # Check if it's a directory and delete accordingly
            if (Test-IsDirectory $item) {
                Write-Host "Deleting directory: $itemName" -ForegroundColor Gray
                Remove-AzStorageDirectory -ShareName $FileShareName -Path $itemName -Context $context -Force -ErrorAction Stop
                $deletedCount++
            } else {
                Write-Host "Deleting file: $itemName" -ForegroundColor Gray
                Remove-AzStorageFile -ShareName $FileShareName -Path $itemName -Context $context -ErrorAction Stop
                $deletedCount++
            }
        } catch {
            Write-Host "⚠️  Failed to delete $itemName : $($_.Exception.Message)" -ForegroundColor Yellow
            $failedCount++
        }
    }
    
    # Summary
    Write-Host ""
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host "✅ Cleanup completed!" -ForegroundColor Green
    Write-Host "   Items deleted: $deletedCount" -ForegroundColor Green
    if ($protectedItems.Count -gt 0) {
        Write-Host "   Protected items preserved: $($protectedItems.Count)" -ForegroundColor Cyan
    }
    if ($failedCount -gt 0) {
        Write-Host "   Items failed: $failedCount" -ForegroundColor Yellow
    }
    Write-Host "=======================================" -ForegroundColor Cyan
    
    # Verification: List remaining files to ensure cleanup was successful
    Write-Host ""
    Write-Host "🔍 Verifying cleanup..." -ForegroundColor Green
    Write-Host "Listing remaining files in file share..." -ForegroundColor Yellow
    
    try {
        $remainingItems = Get-AzStorageFile -ShareName $FileShareName -Context $context -ErrorAction Stop
        
        if ($remainingItems.Count -eq 0) {
            Write-Host "✅ File share is now completely empty" -ForegroundColor Green
        } else {
            Write-Host "📁 Remaining items in file share: $($remainingItems.Count)" -ForegroundColor Cyan
            foreach ($item in $remainingItems) {
                $itemType = if (Test-IsDirectory $item) { "Directory" } else { "File" }
                $protectedMarker = if ($protectedFolders -contains $item.Name) { " [PROTECTED]" } else { "" }
                Write-Host "   - $($item.Name) ($itemType)$protectedMarker" -ForegroundColor Gray
            }
            
            # Check if only protected items remain
            $unprotectedRemaining = $remainingItems | Where-Object { -not ($protectedFolders -contains $_.Name) }
            if ($unprotectedRemaining.Count -eq 0) {
                Write-Host "✅ All non-protected items were successfully deleted" -ForegroundColor Green
            } else {
                Write-Host "⚠️  Warning: $($unprotectedRemaining.Count) non-protected item(s) still remain" -ForegroundColor Yellow
                Write-Host "   These items may have failed to delete or were added during cleanup" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "⚠️  Could not verify cleanup: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "   Cleanup may have succeeded, but verification failed" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "=======================================" -ForegroundColor Cyan
    
    # Exit with success if most items were deleted
    if ($failedCount -eq 0) {
        exit 0
    } elseif ($deletedCount -gt $failedCount) {
        Write-Host "⚠️  Some items failed to delete, but cleanup was mostly successful" -ForegroundColor Yellow
        exit 0
    } else {
        Write-Host "❌ Too many items failed to delete" -ForegroundColor Red
        exit 1
    }
    
} catch {
    Write-Host ""
    Write-Host "❌ ERROR: Failed to clear file share" -ForegroundColor Red
    Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    
    # Print stack trace for debugging
    Write-Host "Stack trace:" -ForegroundColor Gray
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    
    exit 1
}

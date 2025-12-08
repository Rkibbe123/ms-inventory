#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Clears all files and directories from an Azure Storage File Share.

.DESCRIPTION
    This script deletes all files and folders from a specified Azure File Share.
    It is intended to run before Azure Resource Inventory (ARI) execution to ensure
    a clean state for report generation.

.PARAMETER StorageAccountName
    The name of the Azure Storage Account.

.PARAMETER StorageAccountKey
    The access key for the Azure Storage Account.

.PARAMETER FileShareName
    The name of the Azure File Share to clear.

.EXAMPLE
    ./clear-azure-fileshare.ps1 -StorageAccountName "mystorageacct" -StorageAccountKey "abc123..." -FileShareName "ari-data"
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

Write-Host "🧹 Azure File Share Cleanup" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "Storage Account: $StorageAccountName" -ForegroundColor Yellow
Write-Host "File Share: $FileShareName" -ForegroundColor Yellow
Write-Host ""

try {
    # Create storage context
    Write-Host "Connecting to Azure Storage..." -ForegroundColor Green
    
    # Import the Az.Storage module if not already loaded
    if (-not (Get-Module -Name Az.Storage -ListAvailable)) {
        Write-Host "Installing Az.Storage module..." -ForegroundColor Yellow
        Install-Module -Name Az.Storage -Force -Scope CurrentUser -AllowClobber
    }
    
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
    
    if ($items.Count -eq 0) {
        Write-Host "✅ File share is already empty. Nothing to delete." -ForegroundColor Green
        exit 0
    }
    
    Write-Host "Found $($items.Count) items to delete" -ForegroundColor Yellow
    
    # Delete each item (files and directories)
    $deletedCount = 0
    $failedCount = 0
    
    foreach ($item in $items) {
        try {
            $itemName = $item.Name
            
            if ($item.GetType().Name -eq 'AzureStorageFileDirectory' -or $item.IsDirectory) {
                # It's a directory - delete recursively
                Write-Host "Deleting directory: $itemName" -ForegroundColor Gray
                Remove-AzStorageDirectory -ShareName $FileShareName -Path $itemName -Context $context -Force -ErrorAction Stop
                $deletedCount++
            } else {
                # It's a file
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
    if ($failedCount -gt 0) {
        Write-Host "   Items failed: $failedCount" -ForegroundColor Yellow
    }
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

#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test script for Azure File Share cleanup functionality.

.DESCRIPTION
    This script tests the clear-azure-fileshare.ps1 script by validating:
    - PowerShell syntax
    - Function definitions
    - Error handling logic
    - Configuration parameters
    - Logging functionality

.NOTES
    This is a unit test that does NOT require actual Azure credentials.
    It validates the script structure and logic without connecting to Azure.
#>

$ErrorActionPreference = 'Stop'

Write-Host "=== AZURE FILE SHARE CLEANUP SCRIPT TEST ===" -ForegroundColor Cyan
Write-Host ""

$scriptPath = Join-Path $PSScriptRoot "powershell/clear-azure-fileshare.ps1"
$testResults = @{
    Passed = 0
    Failed = 0
    Tests = @()
}

function Test-Result {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = ""
    )
    
    if ($Passed) {
        Write-Host "✅ PASS: $TestName" -ForegroundColor Green
        $script:testResults.Passed++
    } else {
        Write-Host "❌ FAIL: $TestName" -ForegroundColor Red
        if ($Message) {
            Write-Host "   Error: $Message" -ForegroundColor Yellow
        }
        $script:testResults.Failed++
    }
    
    $script:testResults.Tests += @{
        Name = $TestName
        Passed = $Passed
        Message = $Message
    }
}

# Test 1: Script file exists
Write-Host "Test 1: Checking if script file exists..." -ForegroundColor Yellow
$fileExists = Test-Path $scriptPath
Test-Result -TestName "Script file exists" -Passed $fileExists -Message $(if (-not $fileExists) { "File not found at $scriptPath" })

if (-not $fileExists) {
    Write-Host ""
    Write-Host "Cannot continue tests without script file." -ForegroundColor Red
    exit 1
}

# Test 2: PowerShell syntax validation
Write-Host "Test 2: Validating PowerShell syntax..." -ForegroundColor Yellow
try {
    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    
    if ($errors.Count -eq 0) {
        Test-Result -TestName "PowerShell syntax validation" -Passed $true
    } else {
        $errorMessages = $errors | ForEach-Object { $_.Message } | Out-String
        Test-Result -TestName "PowerShell syntax validation" -Passed $false -Message "Syntax errors found: $errorMessages"
    }
} catch {
    Test-Result -TestName "PowerShell syntax validation" -Passed $false -Message $_.Exception.Message
}

# Test 3: Check for required parameters
Write-Host "Test 3: Checking for required parameters..." -ForegroundColor Yellow
$scriptContent = Get-Content $scriptPath -Raw
$requiredParams = @('StorageAccountName', 'StorageAccountKey', 'FileShareName')
$allParamsFound = $true
$missingParams = @()

foreach ($param in $requiredParams) {
    if ($scriptContent -notmatch "param\s*\([\s\S]*?\[\s*Parameter\s*\(\s*Mandatory\s*=\s*\`$true\s*\)\s*\]\s*\[string\]\s*\`$$param") {
        $allParamsFound = $false
        $missingParams += $param
    }
}

if ($allParamsFound) {
    Test-Result -TestName "Required parameters defined" -Passed $true
} else {
    Test-Result -TestName "Required parameters defined" -Passed $false -Message "Missing required parameters: $($missingParams -join ', ')"
}

# Test 4: Check for enhanced retry configuration
Write-Host "Test 4: Checking for enhanced retry configuration..." -ForegroundColor Yellow
$hasMaxRetries = $scriptContent -match '\$MaxRetries\s*=\s*\d+'
$hasRetryDelay = $scriptContent -match '\$RetryDelaySeconds\s*=\s*\d+'
$hasMaxRetryDelay = $scriptContent -match '\$MaxRetryDelaySeconds\s*=\s*\d+'

$retryConfigOk = $hasMaxRetries -and $hasRetryDelay -and $hasMaxRetryDelay
Test-Result -TestName "Enhanced retry configuration" -Passed $retryConfigOk -Message $(if (-not $retryConfigOk) { "Missing retry configuration variables" })

# Test 5: Check for Test-IsTransientError function
Write-Host "Test 5: Checking for transient error detection..." -ForegroundColor Yellow
$hasTransientErrorFunction = $scriptContent -match 'function\s+Test-IsTransientError'
Test-Result -TestName "Transient error detection function" -Passed $hasTransientErrorFunction -Message $(if (-not $hasTransientErrorFunction) { "Test-IsTransientError function not found" })

# Test 6: Check for ResourceNotFound error handling
Write-Host "Test 6: Checking for ResourceNotFound error handling..." -ForegroundColor Yellow
$hasResourceNotFoundHandling = $scriptContent -match 'ResourceNotFound'
Test-Result -TestName "ResourceNotFound error handling" -Passed $hasResourceNotFoundHandling -Message $(if (-not $hasResourceNotFoundHandling) { "ResourceNotFound error handling not found" })

# Test 7: Check for file existence validation
Write-Host "Test 7: Checking for file existence validation..." -ForegroundColor Yellow
$hasExistenceValidation = $scriptContent -match 'Validating existence'
Test-Result -TestName "File existence validation" -Passed $hasExistenceValidation -Message $(if (-not $hasExistenceValidation) { "File existence validation not found" })

# Test 8: Check for enhanced statistics tracking
Write-Host "Test 8: Checking for enhanced statistics..." -ForegroundColor Yellow
$hasResourceNotFoundCount = $scriptContent -match '\$script:ResourceNotFoundCount'
$hasTransientErrorCount = $scriptContent -match '\$script:TransientErrorCount'
$hasEnhancedStats = $hasResourceNotFoundCount -and $hasTransientErrorCount
Test-Result -TestName "Enhanced statistics tracking" -Passed $hasEnhancedStats -Message $(if (-not $hasEnhancedStats) { "Enhanced statistics variables not found" })

# Test 9: Check for exponential backoff implementation
Write-Host "Test 9: Checking for exponential backoff..." -ForegroundColor Yellow
$hasExponentialBackoff = $scriptContent -match '\$currentDelay\s*\*\s*2'
Test-Result -TestName "Exponential backoff implementation" -Passed $hasExponentialBackoff -Message $(if (-not $hasExponentialBackoff) { "Exponential backoff logic not found" })

# Test 10: Check for Write-Log function
Write-Host "Test 10: Checking for logging function..." -ForegroundColor Yellow
$hasWriteLogFunction = $scriptContent -match 'function\s+Write-Log'
$hasLogLevels = $scriptContent -match "ValidateSet\('INFO',\s*'WARNING',\s*'ERROR',\s*'SUCCESS'\)"
$hasLogging = $hasWriteLogFunction -and $hasLogLevels
Test-Result -TestName "Logging functionality" -Passed $hasLogging -Message $(if (-not $hasLogging) { "Write-Log function or log levels not properly defined" })

# Test 11: Check for error context in logs
Write-Host "Test 11: Checking for detailed error context..." -ForegroundColor Yellow
$hasErrorType = $scriptContent -match 'Error Type:'
$hasErrorMessage = $scriptContent -match 'Error Message:'
$hasItemPath = $scriptContent -match 'Item Path:'
$hasDetailedContext = $hasErrorType -and $hasErrorMessage -and $hasItemPath
Test-Result -TestName "Detailed error context in logs" -Passed $hasDetailedContext -Message $(if (-not $hasDetailedContext) { "Detailed error context not found" })

# Test 12: Check for improved troubleshooting guidance
Write-Host "Test 12: Checking for troubleshooting guidance..." -ForegroundColor Yellow
$hasTroubleshooting = $scriptContent -match 'Troubleshooting steps:'
$hasCaseSensitivityGuidance = $scriptContent -match 'case sensitivity'
$hasNetworkGuidance = $scriptContent -match 'network'
$hasGuidance = $hasTroubleshooting -and $hasCaseSensitivityGuidance -and $hasNetworkGuidance
Test-Result -TestName "Improved troubleshooting guidance" -Passed $hasGuidance -Message $(if (-not $hasGuidance) { "Troubleshooting guidance incomplete" })

# Test 13: Validate retry count increased from 3 to 5
Write-Host "Test 13: Checking if retry count was increased..." -ForegroundColor Yellow
$retryCountMatch = $scriptContent -match '\$MaxRetries\s*=\s*(\d+)'
if ($Matches -and $Matches[1] -ge 5) {
    Test-Result -TestName "Retry count increased to 5 or more" -Passed $true
} else {
    Test-Result -TestName "Retry count increased to 5 or more" -Passed $false -Message "MaxRetries should be 5 or more, found: $($Matches[1])"
}

# Test 14: Check for protected items handling
Write-Host "Test 14: Checking for protected items handling..." -ForegroundColor Yellow
$hasProtectedCheck = $scriptContent -match 'function\s+Test-IsProtected'
$hasProtectedFolders = $scriptContent -match '\.jobs'
$hasProtectedHandling = $hasProtectedCheck -and $hasProtectedFolders
Test-Result -TestName "Protected items handling" -Passed $hasProtectedHandling -Message $(if (-not $hasProtectedHandling) { "Protected items handling not found" })

# Test 15: Check for cleanup verification
Write-Host "Test 15: Checking for cleanup verification..." -ForegroundColor Yellow
$hasVerification = $scriptContent -match 'Verifying cleanup'
Test-Result -TestName "Cleanup verification" -Passed $hasVerification -Message $(if (-not $hasVerification) { "Cleanup verification not found" })

# Test 16: Check for directory recreation functionality
Write-Host "Test 16: Checking for directory recreation..." -ForegroundColor Yellow
$hasRecreateFunction = $scriptContent -match 'function\s+New-DirectoryWithRetry'
$hasDirectoriesToRecreate = $scriptContent -match '\$DirectoriesToRecreate'
$hasRecreateLogic = $scriptContent -match 'Recreating required directories'
$hasRecreation = $hasRecreateFunction -and $hasDirectoriesToRecreate -and $hasRecreateLogic
Test-Result -TestName "Directory recreation functionality" -Passed $hasRecreation -Message $(if (-not $hasRecreation) { "Directory recreation logic not found" })

# Test 17: Check for extended delay after directory deletion
Write-Host "Test 17: Checking for directory consistency delay..." -ForegroundColor Yellow
$hasConsistencyDelay = $scriptContent -match '\$DirectoryConsistencyDelaySeconds'
$hasDelayAfterDeletion = $scriptContent -match 'Waiting.*seconds for Azure API consistency'
$hasExtendedDelay = $hasConsistencyDelay -and $hasDelayAfterDeletion
Test-Result -TestName "Extended directory deletion delay" -Passed $hasExtendedDelay -Message $(if (-not $hasExtendedDelay) { "Extended delay after directory deletion not found" })

# Test 18: Check for RecreatedCount statistic
Write-Host "Test 18: Checking for directory recreation statistics..." -ForegroundColor Yellow
$hasRecreatedCount = $scriptContent -match '\$script:RecreatedCount'
$hasRecreatedInStats = $scriptContent -match 'Directories recreated:'
$hasRecreationStats = $hasRecreatedCount -and $hasRecreatedInStats
Test-Result -TestName "Directory recreation statistics" -Passed $hasRecreationStats -Message $(if (-not $hasRecreationStats) { "Directory recreation statistics not found" })

# Test 19: Check for AzureResourceInventory directory in recreation list
Write-Host "Test 19: Checking for AzureResourceInventory directory recreation..." -ForegroundColor Yellow
$hasAzureResourceInventory = $scriptContent -match "'AzureResourceInventory'"
Test-Result -TestName "AzureResourceInventory directory in recreation list" -Passed $hasAzureResourceInventory -Message $(if (-not $hasAzureResourceInventory) { "AzureResourceInventory directory not in recreation list" })

# Display final results
Write-Host ""
Write-Host "=== TEST RESULTS ===" -ForegroundColor Cyan
Write-Host "Total Tests: $($testResults.Passed + $testResults.Failed)" -ForegroundColor White
Write-Host "Passed: $($testResults.Passed)" -ForegroundColor Green
Write-Host "Failed: $($testResults.Failed)" -ForegroundColor $(if ($testResults.Failed -gt 0) { 'Red' } else { 'Green' })
Write-Host ""

if ($testResults.Failed -eq 0) {
    Write-Host "✅ ALL TESTS PASSED!" -ForegroundColor Green
    Write-Host ""
    Write-Host "The cleanup script has been successfully enhanced with:" -ForegroundColor Cyan
    Write-Host "  ✓ ResourceNotFound error handling" -ForegroundColor White
    Write-Host "  ✓ Exponential backoff retry logic" -ForegroundColor White
    Write-Host "  ✓ File existence validation" -ForegroundColor White
    Write-Host "  ✓ Transient error detection" -ForegroundColor White
    Write-Host "  ✓ Enhanced logging and statistics" -ForegroundColor White
    Write-Host "  ✓ Improved troubleshooting guidance" -ForegroundColor White
    Write-Host "  ✓ Directory recreation after deletion" -ForegroundColor White
    Write-Host "  ✓ Extended delays for Azure API consistency" -ForegroundColor White
    Write-Host ""
    exit 0
} else {
    Write-Host "❌ SOME TESTS FAILED" -ForegroundColor Red
    Write-Host "Please review the failures above and fix the issues." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

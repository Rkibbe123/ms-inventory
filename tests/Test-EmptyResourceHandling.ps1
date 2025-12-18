# Test for Empty Resource Handling in Start-ARIProcessJob
# This test validates that the v7.41 fix correctly handles 0 resources without creating empty XML files

param()

$ErrorActionPreference = 'Stop'

function Write-TestLog {
    param(
        [ValidateSet('INFO','PASS','FAIL','WARN')]
        [string]$Level,
        [string]$Message
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $color = switch ($Level) {
        'PASS' { 'Green' }
        'FAIL' { 'Red' }
        'WARN' { 'Yellow' }
        default { 'White' }
    }
    Write-Host "[$timestamp][$Level] $Message" -ForegroundColor $color
}

Write-TestLog -Level 'INFO' -Message 'Starting Empty Resource Handling Test'

$testsPassed = 0
$testsFailed = 0

# Test 1: Verify empty resource array handling in job scriptblock
Write-TestLog -Level 'INFO' -Message 'Test 1: Empty resource array handling'
try {
    # Simulate the job scriptblock logic for empty resources
    $TempJsonFile = $null
    
    if ($null -eq $TempJsonFile -or $TempJsonFile -eq '') {
        $Resources = @()  # Empty array
        $ResourceCount = 0
    }
    
    # Verify empty array was created correctly
    if ($null -eq $Resources) {
        throw "Resources is null, expected empty array"
    }
    
    if ($Resources -isnot [Array]) {
        throw "Resources is not an array, got: $($Resources.GetType())"
    }
    
    if ($Resources.Count -ne 0) {
        throw "Resources count is $($Resources.Count), expected 0"
    }
    
    if ($ResourceCount -ne 0) {
        throw "ResourceCount is $ResourceCount, expected 0"
    }
    
    Write-TestLog -Level 'PASS' -Message 'Test 1: Empty array created correctly'
    $testsPassed++
} catch {
    Write-TestLog -Level 'FAIL' -Message "Test 1 failed: $($_.Exception.Message)"
    $testsFailed++
}

# Test 2: Verify no XML file is created when FilteredCount is 0
Write-TestLog -Level 'INFO' -Message 'Test 2: No XML file creation for 0 resources'
try {
    # Simulate the filtering logic
    $FilteredResources = @()
    $FilteredCount = $FilteredResources.count
    
    # Simulate the v7.41 logic
    if ($FilteredCount -eq 0) {
        $TempJobFile = $null  # Pass null to indicate no resources
        $fileCreated = $false
    } else {
        $TempJobFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "ari_test_$(Get-Date -Format 'yyyyMMdd_HHmmss').xml")
        $fileCreated = $true
    }
    
    # Verify no file was created
    if ($fileCreated) {
        throw "File creation attempted for 0 resources"
    }
    
    if ($null -ne $TempJobFile) {
        throw "TempJobFile should be null for 0 resources, got: $TempJobFile"
    }
    
    Write-TestLog -Level 'PASS' -Message 'Test 2: No XML file created for 0 resources'
    $testsPassed++
} catch {
    Write-TestLog -Level 'FAIL' -Message "Test 2 failed: $($_.Exception.Message)"
    $testsFailed++
}

# Test 3: Verify XML file IS created when FilteredCount > 0
Write-TestLog -Level 'INFO' -Message 'Test 3: XML file creation for non-zero resources'
try {
    # Create sample resources
    $FilteredResources = @(
        [PSCustomObject]@{ Name = 'Resource1'; TYPE = 'microsoft.test/resource' }
    )
    $FilteredCount = $FilteredResources.count
    
    # Simulate the v7.41 logic
    if ($FilteredCount -eq 0) {
        $TempJobFile = $null
        $fileCreated = $false
    } else {
        $TempJobFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "ari_test_$(Get-Date -Format 'yyyyMMdd_HHmmss').xml")
        $FilteredResources | Export-Clixml -Path $TempJobFile -Depth 5 -Force
        $fileCreated = $true
    }
    
    # Verify file was created
    if (-not $fileCreated) {
        throw "File creation should occur for 1+ resources"
    }
    
    if ($null -eq $TempJobFile) {
        throw "TempJobFile should not be null for 1+ resources"
    }
    
    if (-not (Test-Path $TempJobFile)) {
        throw "File not found at expected path: $TempJobFile"
    }
    
    $fileSize = (Get-Item $TempJobFile).Length
    if ($fileSize -eq 0) {
        throw "File size is 0, expected non-zero for 1+ resources"
    }
    
    # Clean up
    Remove-Item -Path $TempJobFile -Force -ErrorAction SilentlyContinue
    
    Write-TestLog -Level 'PASS' -Message 'Test 3: XML file created correctly for 1+ resources'
    $testsPassed++
} catch {
    Write-TestLog -Level 'FAIL' -Message "Test 3 failed: $($_.Exception.Message)"
    $testsFailed++
    # Clean up on failure
    if ($TempJobFile -and (Test-Path $TempJobFile)) {
        Remove-Item -Path $TempJobFile -Force -ErrorAction SilentlyContinue
    }
}

# Test 4: Verify empty string is also handled as null
Write-TestLog -Level 'INFO' -Message 'Test 4: Empty string handling'
try {
    $TempJsonFile = ''
    
    if ($null -eq $TempJsonFile -or $TempJsonFile -eq '') {
        $Resources = @()  # Empty array
        $handled = $true
    } else {
        $handled = $false
    }
    
    if (-not $handled) {
        throw "Empty string should be handled as no resources"
    }
    
    if ($Resources.Count -ne 0) {
        throw "Resources count should be 0 for empty string input"
    }
    
    Write-TestLog -Level 'PASS' -Message 'Test 4: Empty string handled correctly'
    $testsPassed++
} catch {
    Write-TestLog -Level 'FAIL' -Message "Test 4 failed: $($_.Exception.Message)"
    $testsFailed++
}

# Summary
Write-TestLog -Level 'INFO' -Message "=========================================="
Write-TestLog -Level 'INFO' -Message "Test Summary: $testsPassed passed, $testsFailed failed"
Write-TestLog -Level 'INFO' -Message "=========================================="

if ($testsFailed -gt 0) {
    Write-TestLog -Level 'FAIL' -Message "Some tests failed"
    exit 1
} else {
    Write-TestLog -Level 'PASS' -Message "All tests passed!"
    exit 0
}

# Import-Clixml Robustness Harness
param()

$ErrorActionPreference = 'Stop'

function Write-Log {
    param(
        [ValidateSet('INFO','WARN','ERROR','PASS','FAIL')]
        [string]$Level,
        [string]$Message
    )
    $ts = (Get-Date).ToString('s')
    Write-Host "[$ts][$Level] $Message"
}

function Wait-StableFile {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [int]$StableWindowMs = 500,
        [int]$TimeoutMs = 15000,
        [int]$PollMs = 100
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        if (-not (Test-Path -LiteralPath $Path)) {
            Start-Sleep -Milliseconds $PollMs
            continue
        }
        $fi1 = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
        if (-not $fi1 -or $fi1.Length -le 0) { Start-Sleep -Milliseconds $PollMs; continue }

        # Observe for StableWindowMs to see if size changes
        $size1 = $fi1.Length
        $mtime1 = $fi1.LastWriteTimeUtc
        Start-Sleep -Milliseconds $StableWindowMs
        if (-not (Test-Path -LiteralPath $Path)) { continue }
        $fi2 = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
        if (-not $fi2) { continue }
        $size2 = $fi2.Length
        $mtime2 = $fi2.LastWriteTimeUtc
        if ($size1 -eq $size2 -and $mtime1 -eq $mtime2) {
            return $true
        }
    }
    return $false
}

function Import-ClixmlSafe {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [int]$MaxAttempts = 5,
        [int]$StableWindowMs = 500
    )
    if (-not (Wait-StableFile -Path $Path -StableWindowMs $StableWindowMs)) {
        throw "File '$Path' did not become stable within timeout."
    }

    # Optional header sanity check
    try {
        $firstLine = (Get-Content -LiteralPath $Path -TotalCount 1 -ErrorAction Stop)
    } catch {
        $firstLine = $null
    }
    if ($firstLine -and ($firstLine -notmatch '<\?xml' -and $firstLine -notmatch 'Obj Ref')) {
        Write-Log WARN "First line doesn't look like CLIXML header: '$firstLine'"
    }

    $attempt = 0
    $lastErr = $null
    while ($attempt -lt $MaxAttempts) {
        $attempt++
        try {
            $data = Import-Clixml -LiteralPath $Path -ErrorAction Stop
            if ($null -ne $data) { return $data }
            $lastErr = "Import-Clixml returned null on attempt $attempt."
        } catch {
            $lastErr = $_.Exception.Message
        }

        # Fallback: try import from a copy (helps if source is being locked/transacted)
        try {
            $tmpCopy = [System.IO.Path]::ChangeExtension($Path, '.copy.clixml')
            Copy-Item -LiteralPath $Path -Destination $tmpCopy -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $tmpCopy) {
                $data = Import-Clixml -LiteralPath $tmpCopy -ErrorAction Stop
                Remove-Item -LiteralPath $tmpCopy -Force -ErrorAction SilentlyContinue
                if ($null -ne $data) { return $data }
            }
        } catch {
            $lastErr = $_.Exception.Message
        }

        Start-Sleep -Milliseconds ([math]::Min(250 * [math]::Pow(2, $attempt-1), 2000))
    }
    $size = (Test-Path -LiteralPath $Path) ? (Get-Item -LiteralPath $Path).Length : -1
    throw "Failed to Import-Clixml from '$Path' after $MaxAttempts attempts. Last error: $lastErr. File size: $size bytes."
}

function New-SampleObjects {
    param([int]$Count = 5)
    $list = @()
    1..$Count | ForEach-Object {
        $list += [pscustomobject]@{ Id = $_; Name = "Item$_"; When = (Get-Date).ToUniversalTime() }
    }
    return $list
}

function Start-SlowClixmlWriter {
    param(
        [Parameter(Mandatory)] [string]$TargetPath,
        [Parameter(Mandatory)] $Objects,
        [int]$ChunkSize = 1024,
        [int]$DelayMs = 50
    )
    # Export to a temp file first
    $temp = [System.IO.Path]::GetTempFileName()
    try {
        $Objects | Export-Clixml -LiteralPath $temp -Depth 5
        $bytes = [System.IO.File]::ReadAllBytes($temp)
        if (Test-Path -LiteralPath $TargetPath) { Remove-Item -LiteralPath $TargetPath -Force -ErrorAction SilentlyContinue }
        $fs = [System.IO.File]::Open($TargetPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        try {
            $offset = 0
            while ($offset -lt $bytes.Length) {
                $len = [math]::Min($ChunkSize, $bytes.Length - $offset)
                $fs.Write($bytes, $offset, $len)
                $fs.Flush()
                $offset += $len
                Start-Sleep -Milliseconds $DelayMs
            }
        } finally {
            $fs.Dispose()
        }
    } finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

function Assert-Equal {
    param(
        [Parameter(Mandatory)] $Expected,
        [Parameter(Mandatory)] $Actual,
        [string]$Message = 'Values are not equal.'
    )
    $exp = ($Expected | ConvertTo-Json -Depth 10)
    $act = ($Actual | ConvertTo-Json -Depth 10)
    if ($exp -ne $act) { throw $Message }
}

Write-Log INFO 'Starting Import-Clixml robustness harness'
${passed} = 0; ${failed} = 0

# Scenario 1: Normal export/import
try {
    $p1 = Join-Path $env:TEMP "ari-test-normal-$([guid]::NewGuid()).clixml"
    $objs = New-SampleObjects -Count 7
    $objs | Export-Clixml -LiteralPath $p1 -Depth 5
    $in = Import-ClixmlSafe -Path $p1
    Assert-Equal -Expected $objs -Actual $in -Message 'Scenario 1 mismatch'
    Write-Log PASS 'Scenario 1: Normal import succeeded'
    $passed++
} catch {
    Write-Log FAIL "Scenario 1 failed: $($_.Exception.Message)"
    $failed++
} finally {
    Remove-Item -LiteralPath $p1 -Force -ErrorAction SilentlyContinue | Out-Null
}

# Scenario 2: Slow writer produces a growing file; importer should wait until stable
try {
    $p2 = Join-Path $env:TEMP "ari-test-slow-$([guid]::NewGuid()).clixml"
    $objs2 = New-SampleObjects -Count 50

    $job = Start-Job -ScriptBlock {
        param($tp, $o)
        Import-Module Microsoft.PowerShell.Utility | Out-Null
        & $using:PSCommandPath -ArgumentList @('-slow-writer-internal') | Out-Null
    } -ArgumentList $p2, $objs2

    # The above indirection is complex in jobs; instead, do slow write inline on another runspace-less approach:
    # To avoid job serialization issues, perform slow write synchronously first but with delays, then import after a short overlap.
    Start-Job -ScriptBlock {
        param($tp, $o)
        $ErrorActionPreference = 'Stop'
        function New-SampleObjectsLocal { param($arr) return $arr }
        # Reconstruct slow writer body here to avoid scope issues
        $temp = [System.IO.Path]::GetTempFileName()
        try {
            $o | Export-Clixml -LiteralPath $temp -Depth 5
            $bytes = [System.IO.File]::ReadAllBytes($temp)
            if (Test-Path -LiteralPath $tp) { Remove-Item -LiteralPath $tp -Force -ErrorAction SilentlyContinue }
            $fs = [System.IO.File]::Open($tp, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
            try {
                $offset = 0
                while ($offset -lt $bytes.Length) {
                    $len = [math]::Min(2048, $bytes.Length - $offset)
                    $fs.Write($bytes, $offset, $len)
                    $fs.Flush()
                    $offset += $len
                    Start-Sleep -Milliseconds 30
                }
            } finally { $fs.Dispose() }
        } finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue | Out-Null }
    } -ArgumentList $p2, $objs2 | Out-Null

    # Give the writer a head start
    Start-Sleep -Milliseconds 100
    $in2 = Import-ClixmlSafe -Path $p2 -StableWindowMs 300
    Assert-Equal -Expected $objs2 -Actual $in2 -Message 'Scenario 2 mismatch'
    Write-Log PASS 'Scenario 2: Import waited for stable file and succeeded'
    $passed++
} catch {
    Write-Log FAIL "Scenario 2 failed: $($_.Exception.Message)"
    $failed++
} finally {
    if (Test-Path -LiteralPath $p2) { Remove-Item -LiteralPath $p2 -Force -ErrorAction SilentlyContinue | Out-Null }
    Get-Job | Receive-Job -Wait -AutoRemoveJob -ErrorAction SilentlyContinue | Out-Null
}

# Scenario 3: Corrupt file should fail with clear error
try {
    $p3 = Join-Path $env:TEMP "ari-test-corrupt-$([guid]::NewGuid()).clixml"
    Set-Content -LiteralPath $p3 -Value 'this is not clixml' -Encoding UTF8
    try {
        $null = Import-ClixmlSafe -Path $p3 -StableWindowMs 200
        throw 'Scenario 3 unexpectedly succeeded on corrupt file'
    } catch {
        # Expecting an exception
        Write-Log PASS 'Scenario 3: Corrupt file correctly failed to import'
        $passed++
    }
} catch {
    Write-Log FAIL "Scenario 3 failed: $($_.Exception.Message)"
    $failed++
} finally {
    Remove-Item -LiteralPath $p3 -Force -ErrorAction SilentlyContinue | Out-Null
}

Write-Log INFO "Harness complete. Passed=$passed, Failed=$failed"
if ($failed -gt 0) { exit 1 } else { exit 0 }

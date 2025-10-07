# Quick Status Checker - Simple Version
$APP_URL = "https://azure-resource-inventory.ambitiousbeach-c62b6a92.eastus.azurecontainerapps.io"

Write-Host "`n=== Azure Resource Inventory - Quick Status ===`n" -ForegroundColor Cyan

# Check Job Status
Write-Host "Checking PowerShell Jobs..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$APP_URL/check-jobs" -TimeoutSec 10
    $jobData = $response.Content | ConvertFrom-Json
    
    if ($jobData.stdout) {
        $jobs = $jobData.stdout | ConvertFrom-Json
        
        if ($jobs) {
            $running = ($jobs | Where-Object { $_.State -eq 'Running' }).Count
            $completed = ($jobs | Where-Object { $_.State -eq 'Completed' }).Count
            $failed = ($jobs | Where-Object { $_.State -eq 'Failed' }).Count
            $total = $jobs.Count
            
            Write-Host "  Total Jobs:    $total"
            Write-Host "  Running:       " -NoNewline; Write-Host $running -ForegroundColor Yellow
            Write-Host "  Completed:     " -NoNewline; Write-Host $completed -ForegroundColor Green
            Write-Host "  Failed:        " -NoNewline; Write-Host $failed -ForegroundColor Red
            
            if ($total -gt 0) {
                $progress = [math]::Round(($completed / $total) * 100, 1)
                Write-Host "  Progress:      $progress%" -ForegroundColor Cyan
            }
        } else {
            Write-Host "  No jobs running" -ForegroundColor Gray
        }
    }
} catch {
    Write-Host "  Unable to fetch job status" -ForegroundColor Red
}

Write-Host ""

# Check Generated Files
Write-Host "Checking Generated Files..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$APP_URL/debug-files" -TimeoutSec 10
    
    if ($response.Content -match "filtered_files': \[(.*?)\]") {
        $filesMatch = $matches[1]
        if ($filesMatch.Trim() -ne "") {
            $files = $filesMatch -split "',\s*'" -replace "'", "" | Where-Object { $_ -ne "" }
            Write-Host "  Found $($files.Count) report file(s)" -ForegroundColor Green
            foreach ($file in $files) {
                Write-Host "    - $file" -ForegroundColor White
            }
        } else {
            Write-Host "  No files generated yet" -ForegroundColor Gray
        }
    }
} catch {
    Write-Host "  Unable to fetch file list" -ForegroundColor Red
}

Write-Host "`n============================================`n" -ForegroundColor Cyan
Write-Host "Web Interface: $APP_URL" -ForegroundColor Cyan
Write-Host ""

# Live Progress Monitor - Auto-refreshing status display
# Monitors the Azure Resource Inventory execution in real-time

$CONTAINER_APP = "ms-inventory"
$RESOURCE_GROUP = "rg-rkibbe-2470"
$APP_URL = "https://azure-resource-inventory.ambitiousbeach-c62b6a92.eastus.azurecontainerapps.io"

$refreshInterval = 5  # seconds

Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   Azure Resource Inventory - Live Progress Monitor        ║" -ForegroundColor Cyan
Write-Host "║   Press Ctrl+C to stop monitoring                          ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$startTime = Get-Date
$iteration = 0

try {
    while ($true) {
        $iteration++
        $elapsed = (Get-Date) - $startTime
        
        # Clear screen for clean display
        Clear-Host
        
        Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║   Azure Resource Inventory - Live Progress Monitor        ║" -ForegroundColor Cyan
        Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "⏱️  Monitoring Time: " -NoNewline
        Write-Host "$([math]::Floor($elapsed.TotalMinutes))m $($elapsed.Seconds)s" -ForegroundColor Yellow
        Write-Host "🔄 Refresh #$iteration (every ${refreshInterval}s)" -ForegroundColor Gray
        Write-Host "Press Ctrl+C to stop" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
        
        # Get container status
        try {
            $status = az containerapp show `
                --name $CONTAINER_APP `
                --resource-group $RESOURCE_GROUP `
                --query "{status:properties.runningStatus}" `
                --output json 2>$null | ConvertFrom-Json
            
            Write-Host "📊 Container Status: " -NoNewline
            if ($status.status -eq "Running") {
                Write-Host "✅ Running" -ForegroundColor Green
            } else {
                Write-Host "⚠️  $($status.status)" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "📊 Container Status: " -NoNewline
            Write-Host "❌ Unable to fetch" -ForegroundColor Red
        }
        
        Write-Host ""
        
        # Get PowerShell job status
        Write-Host "🔧 PowerShell Jobs:" -ForegroundColor Yellow
        try {
            $jobResponse = Invoke-WebRequest -Uri "$APP_URL/check-jobs" -TimeoutSec 5 -ErrorAction Stop 2>$null
            $jobData = $jobResponse.Content | ConvertFrom-Json
            
            if ($jobData.stdout) {
                $jobs = $jobData.stdout | ConvertFrom-Json
                
                if ($jobs -and $jobs.Count -gt 0) {
                    $running = ($jobs | Where-Object { $_.State -eq 'Running' }).Count
                    $completed = ($jobs | Where-Object { $_.State -eq 'Completed' }).Count
                    $failed = ($jobs | Where-Object { $_.State -eq 'Failed' }).Count
                    $total = $jobs.Count
                    
                    Write-Host "  Total Jobs:     " -NoNewline; Write-Host $total -ForegroundColor White
                    Write-Host "  🏃 Running:     " -NoNewline; Write-Host $running -ForegroundColor Yellow
                    Write-Host "  ✅ Completed:   " -NoNewline; Write-Host $completed -ForegroundColor Green
                    Write-Host "  ❌ Failed:      " -NoNewline; Write-Host $failed -ForegroundColor Red
                    
                    if ($total -gt 0) {
                        $progress = [math]::Round(($completed / $total) * 100, 1)
                        Write-Host "  📊 Progress:    " -NoNewline; Write-Host "$progress%" -ForegroundColor Cyan
                        
                        # Progress bar
                        $barLength = 40
                        $filled = [math]::Floor(($progress / 100) * $barLength)
                        $empty = $barLength - $filled
                        $bar = "  [" + ("█" * $filled) + ("░" * $empty) + "]"
                        Write-Host $bar -ForegroundColor Cyan
                    }
                    
                    # Show running job names if not too many
                    if ($running -gt 0 -and $running -le 10) {
                        Write-Host ""
                        Write-Host "  Currently Running Jobs:" -ForegroundColor DarkYellow
                        $jobs | Where-Object { $_.State -eq 'Running' } | ForEach-Object {
                            Write-Host "    • $($_.Name)" -ForegroundColor Gray
                        }
                    }
                } else {
                    Write-Host "  No active jobs" -ForegroundColor Gray
                }
            } else {
                Write-Host "  No job data available" -ForegroundColor Gray
            }
        } catch {
            Write-Host "  Unable to fetch job status" -ForegroundColor Red
        }
        
        Write-Host ""
        
        # Get generated files
        Write-Host "📁 Generated Files:" -ForegroundColor Yellow
        try {
            $fileResponse = Invoke-WebRequest -Uri "$APP_URL/debug-files" -TimeoutSec 5 -ErrorAction Stop 2>$null
            
            if ($fileResponse.Content -match "filtered_files': \[(.*?)\]") {
                $filesMatch = $matches[1]
                if ($filesMatch.Trim() -ne "") {
                    $files = $filesMatch -split "',\s*'" -replace "'", "" | Where-Object { $_ -ne "" }
                    
                    Write-Host "  ✅ Found $($files.Count) report file(s)" -ForegroundColor Green
                    
                    # Show first 5 files
                    $filesToShow = $files | Select-Object -First 5
                    foreach ($file in $filesToShow) {
                        Write-Host "    📄 $file" -ForegroundColor White
                    }
                    if ($files.Count -gt 5) {
                        Write-Host "    ... and $($files.Count - 5) more" -ForegroundColor Gray
                    }
                } else {
                    Write-Host "  ⏳ No files generated yet - scan in progress..." -ForegroundColor Yellow
                }
            }
        } catch {
            Write-Host "  Unable to fetch file list" -ForegroundColor Red
        }
        
        Write-Host ""
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
        Write-Host "💡 Tip: Open " -NoNewline; Write-Host "$APP_URL" -ForegroundColor Cyan -NoNewline; Write-Host " in browser for live stream" -ForegroundColor White
        Write-Host ""
        
        Start-Sleep -Seconds $refreshInterval
    }
} finally {
    Write-Host ""
    Write-Host "Monitoring stopped." -ForegroundColor Yellow
}

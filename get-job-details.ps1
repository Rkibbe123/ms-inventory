# Get Last Job Output - Fetches the most recent job execution output
# Useful for debugging and seeing what happened in the last run

$APP_URL = "https://azure-resource-inventory.ambitiousbeach-c62b6a92.eastus.azurecontainerapps.io"

Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     Checking Recent Job Execution Output                  ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

try {
    Write-Host "Fetching job status..." -ForegroundColor Yellow
    $response = Invoke-WebRequest -Uri "$APP_URL/check-jobs" -TimeoutSec 10 -ErrorAction Stop
    $jobData = $response.Content | ConvertFrom-Json
    
    if ($jobData.stdout) {
        Write-Host "✅ Successfully retrieved job data" -ForegroundColor Green
        Write-Host ""
        
        # Pretty print the JSON
        $jobs = $jobData.stdout | ConvertFrom-Json
        
        if ($jobs) {
            Write-Host "📊 Job Summary:" -ForegroundColor Yellow
            Write-Host "━━━━━━━━━━━━━━" -ForegroundColor DarkGray
            Write-Host ""
            
            $jobs | Format-Table @{
                Label = "Job Name"
                Expression = { $_.Name }
                Width = 30
            }, @{
                Label = "State"
                Expression = { 
                    switch ($_.State) {
                        "Running" { "🏃 Running" }
                        "Completed" { "✅ Completed" }
                        "Failed" { "❌ Failed" }
                        default { $_.State }
                    }
                }
                Width = 15
            }, @{
                Label = "Has Data"
                Expression = { $_.HasMoreData }
                Width = 10
            }, @{
                Label = "Start Time"
                Expression = { $_.PSBeginTime }
                Width = 20
            }, @{
                Label = "End Time"
                Expression = { $_.PSEndTime }
                Width = 20
            } -AutoSize
            
            Write-Host ""
            Write-Host "📈 Statistics:" -ForegroundColor Yellow
            Write-Host "━━━━━━━━━━━━━" -ForegroundColor DarkGray
            $running = ($jobs | Where-Object { $_.State -eq 'Running' }).Count
            $completed = ($jobs | Where-Object { $_.State -eq 'Completed' }).Count
            $failed = ($jobs | Where-Object { $_.State -eq 'Failed' }).Count
            $total = $jobs.Count
            
            Write-Host "  Total Jobs:    $total"
            Write-Host "  🏃 Running:    $running" -ForegroundColor Yellow
            Write-Host "  ✅ Completed:  $completed" -ForegroundColor Green
            Write-Host "  ❌ Failed:     $failed" -ForegroundColor Red
            
            if ($total -gt 0) {
                $progress = [math]::Round(($completed / $total) * 100, 1)
                Write-Host "  📊 Progress:   $progress%" -ForegroundColor Cyan
            }
            
            Write-Host ""
            
            # Show details of running jobs
            $runningJobs = $jobs | Where-Object { $_.State -eq 'Running' }
            if ($runningJobs) {
                Write-Host "🏃 Currently Running Jobs:" -ForegroundColor Yellow
                Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
                foreach ($job in $runningJobs) {
                    Write-Host "  • $($job.Name)" -ForegroundColor White
                    if ($job.PSBeginTime) {
                        $elapsed = (Get-Date) - [DateTime]$job.PSBeginTime
                        Write-Host "    Running for: $([math]::Floor($elapsed.TotalMinutes))m $($elapsed.Seconds)s" -ForegroundColor Gray
                    }
                }
                Write-Host ""
            }
            
            # Show failed jobs if any
            $failedJobs = $jobs | Where-Object { $_.State -eq 'Failed' }
            if ($failedJobs) {
                Write-Host "❌ Failed Jobs:" -ForegroundColor Red
                Write-Host "━━━━━━━━━━━━━" -ForegroundColor DarkGray
                foreach ($job in $failedJobs) {
                    Write-Host "  • $($job.Name)" -ForegroundColor Red
                }
                Write-Host ""
            }
        } else {
            Write-Host "ℹ️  No jobs found - either none are running or scan hasn't started yet" -ForegroundColor Gray
        }
    } else {
        Write-Host "⚠️  No job data available" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host "💡 For live monitoring, use: " -NoNewline
    Write-Host ".\watch-progress.ps1" -ForegroundColor Cyan
    Write-Host ""
    
} catch {
    Write-Host "❌ Error fetching job status: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "  • Check if the container app is running: .\check-status.ps1" -ForegroundColor White
    Write-Host "  • Verify the URL is accessible: $APP_URL" -ForegroundColor White
    Write-Host ""
}

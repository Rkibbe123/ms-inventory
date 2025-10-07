<#
.Synopsis
Wait for ARI Jobs to Complete

.DESCRIPTION
This script waits for the completion of specified ARI jobs.

.Link
https://github.com/microsoft/ARI/Modules/Public/PublicFunctions/Jobs/Wait-ARIJob.ps1

.COMPONENT
    This powershell Module is part of Azure Resource Inventory (ARI)

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola

#>
function Wait-ARIJob {
    Param($JobNames, $JobType, $LoopTime)

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Jobs Collector.')

    $c = 0
    # ===== ADJUSTED FOR TESTING =====
    $TimeoutMinutes = 15  # Total timeout for all jobs
    $PerJobTimeoutMinutes = 3  # Per-job timeout (increased from 1 to 3 minutes for testing)
    Write-Host "⏱️  TIMEOUT SETTINGS: Total=$TimeoutMinutes min, Per-Job=$PerJobTimeoutMinutes min" -ForegroundColor Yellow
    # ===== END ADJUSTMENT =====
    $StartTime = Get-Date
    $MaxDuration = New-TimeSpan -Minutes $TimeoutMinutes
    $PerJobMaxDuration = New-TimeSpan -Minutes $PerJobTimeoutMinutes
    
    Write-Host "🚨 TIMEOUT MONITOR INITIALIZED - Per-job limit: $PerJobTimeoutMinutes minute(s)" -ForegroundColor Yellow
    
    # Get initial job count and track start times
    $jb = get-job -Name $JobNames -ErrorAction SilentlyContinue
    if ($null -eq $jb -or $jb.Count -eq 0) {
        Write-Warning "CRITICAL: No jobs found with names: $($JobNames -join ', ')"
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"No jobs found to monitor. This may indicate job creation failure.")
        return
    }
    
    Write-Host "📊 Found $($jb.Count) jobs to monitor at $($StartTime.ToString('HH:mm:ss'))" -ForegroundColor Cyan
    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Found $($jb.Count) jobs to monitor. Per-job timeout: $PerJobTimeoutMinutes minutes")
    
    # Track when each job started - use job NAME as key since IDs might change
    $jobStartTimes = @{}
    foreach ($job in $jb) {
        $jobStartTime = if ($job.PSBeginTime) { $job.PSBeginTime } else { $StartTime }
        $jobStartTimes[$job.Name] = $jobStartTime
        Write-Host "  ⏰ $($job.Name): Start=$($jobStartTime.ToString('HH:mm:ss')) Timeout=$($jobStartTime.AddMinutes($PerJobTimeoutMinutes).ToString('HH:mm:ss'))" -ForegroundColor Gray
    }

    Write-Host "🔍 ENTERING MONITORING LOOP - Starting while(true) at $((Get-Date).ToString('HH:mm:ss'))" -ForegroundColor Magenta
    $loopIteration = 0
    
    while ($true) {
        $loopIteration++
        Write-Host "🔄 LOOP ITERATION #$loopIteration at $((Get-Date).ToString('HH:mm:ss'))" -ForegroundColor Cyan
        
        # Output visible progress marker every iteration for web interface
        $elapsedSoFar = (Get-Date) - $StartTime
        $minutes = [math]::Floor($elapsedSoFar.TotalMinutes)
        $seconds = [math]::Floor($elapsedSoFar.TotalSeconds % 60)
        Write-Host "⏱️  Elapsed Time: ${minutes}m ${seconds}s" -ForegroundColor Yellow
        
        Write-Host "   Calling Get-Job..." -ForegroundColor Gray
        $jb = get-job -Name $JobNames -ErrorAction SilentlyContinue
        Write-Host "   Get-Job returned: $($jb.Count) jobs" -ForegroundColor Gray
        
        if ($null -eq $jb) {
            Write-Host "❌ Jobs disappeared during monitoring!" -ForegroundColor Red
            Write-Warning "Jobs disappeared during monitoring!"
            break
        }
        
        Write-Host "   Filtering jobs by state..." -ForegroundColor Gray
        $runningJobs = $jb | Where-Object { $_.State -eq 'Running' }
        $failedJobs = $jb | Where-Object { $_.State -in @('Failed', 'Stopped', 'Blocked') }
        Write-Host "   Running: $($runningJobs.Count) | Failed: $($failedJobs.Count)" -ForegroundColor Gray
        
        # Check for individual job timeouts - use job NAME as key
        $timedOutJobs = @()
        $currentTime = Get-Date
        
        # Force output on every loop - Write-Host cannot be suppressed
        $firstJobName = $runningJobs[0].Name
        if ($jobStartTimes.ContainsKey($firstJobName)) {
            $firstJobRunTime = $currentTime - $jobStartTimes[$firstJobName]
            Write-Host "⏱️ CHECK @ $($currentTime.ToString('HH:mm:ss')): $firstJobName runtime=$([math]::Round($firstJobRunTime.TotalSeconds,0))s / $($PerJobTimeoutMinutes*60)s limit" -ForegroundColor DarkYellow
        }
        
        foreach ($job in $runningJobs) {
            if ($jobStartTimes.ContainsKey($job.Name)) {
                $jobRunTime = $currentTime - $jobStartTimes[$job.Name]
                
                if ($jobRunTime -gt $PerJobMaxDuration) {
                    $timedOutJobs += $job
                    Write-Host "🔥 TIMEOUT! $($job.Name) exceeded $PerJobTimeoutMinutes min - runtime: $([math]::Round($jobRunTime.TotalMinutes, 1)) min" -ForegroundColor Red
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"⏰ INDIVIDUAL JOB TIMEOUT: $($job.Name) has been running for $([math]::Round($jobRunTime.TotalMinutes, 1)) minutes")
                    Write-Warning "Job timeout: $($job.Name) exceeded $PerJobTimeoutMinutes minute limit"
                }
            } else {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"WARNING: No start time tracked for job: $($job.Name)")
            }
        }
        
        # Stop timed out jobs
        if ($timedOutJobs.Count -gt 0) {
            Write-Host "🛑 STOPPING $($timedOutJobs.Count) TIMED-OUT JOBS:" -ForegroundColor Red
            foreach ($job in $timedOutJobs) {
                Write-Host "   Stopping: $($job.Name)" -ForegroundColor Red
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Stopping stuck job: $($job.Name)")
                $job | Stop-Job -ErrorAction SilentlyContinue
            }
            Write-Warning "Stopped $($timedOutJobs.Count) jobs that exceeded $PerJobTimeoutMinutes minute timeout"
        }
        
        # Exit if no more jobs are running
        if ($runningJobs.Count -eq 0) {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'All jobs completed.')
            break
        }
        
        # Check for timeout
        $ElapsedTime = (Get-Date) - $StartTime
        if ($ElapsedTime -gt $MaxDuration) {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"TIMEOUT: Jobs exceeded $TimeoutMinutes minutes. Stopping remaining jobs.")
            Write-Warning "Job timeout reached after $TimeoutMinutes minutes. Stopping stuck jobs."
            
            # Log which jobs are still running
            foreach ($job in $runningJobs) {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"STUCK JOB: $($job.Name) - State: $($job.State)")
            }
            
            # Stop stuck jobs
            $runningJobs | Stop-Job -ErrorAction SilentlyContinue
            break
        }
        
        # Check for failed jobs
        if ($failedJobs.Count -gt 0) {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"WARNING: $($failedJobs.Count) jobs have failed or stopped.")
            foreach ($job in $failedJobs) {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"FAILED JOB: $($job.Name) - State: $($job.State)")
            }
        }
        
        $c = (((($jb.count - $runningJobs.Count) / $jb.Count) * 100))
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"$JobType Jobs Still Running: "+[string]$runningJobs.count)
        
        # Output progress to console for web interface visibility
        Write-Host ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"$JobType Jobs Still Running: "+[string]$runningJobs.count) -ForegroundColor Cyan
        
        # Log detailed job status every 30 seconds (6 loops of 5 seconds)
        $loopCount = [math]::Floor($ElapsedTime.TotalSeconds / $LoopTime)
        if ($loopCount % 6 -eq 0 -and $loopCount -gt 0) {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"DETAILED JOB STATUS (Elapsed: $([math]::Round($ElapsedTime.TotalMinutes, 1)) min)")
            foreach ($job in $jb) {
                $jobInfo = "Job: $($job.Name) | State: $($job.State) | HasMoreData: $($job.HasMoreData) | ChildJobs: $($job.ChildJobs.Count)"
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+$jobInfo)
                
                # Check if job has errors
                if ($job.ChildJobs.Count -gt 0 -and $job.ChildJobs[0].Error.Count -gt 0) {
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"  ERROR in $($job.Name): $($job.ChildJobs[0].Error[0].Exception.Message)")
                }
            }
        }
        
        # Log individual running job names for better visibility
        if ($runningJobs.Count -le 10) {
            $runningJobNames = ($runningJobs | Select-Object -ExpandProperty Name) -join ', '
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Running Jobs: $runningJobNames")
        }
        
        $c = [math]::Round($c)
        Write-Progress -Id 1 -activity "Processing $JobType Jobs" -Status "$c% Complete." -PercentComplete $c
        Start-Sleep -Seconds $LoopTime
    }
    Write-Progress -Id 1 -activity "Processing $JobType Jobs" -Status "100% Complete." -Completed

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Jobs Complete.')
}
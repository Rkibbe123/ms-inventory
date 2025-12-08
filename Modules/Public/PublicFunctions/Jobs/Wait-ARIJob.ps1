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
Version: 3.6.9 - v7.40
First Release Date: 15th Oct, 2024
Authors: Claudio Merola

Changelog:
- v7.40: CRITICAL FIX - Capture job output immediately before PowerShell auto-removes jobs
         Returns hashtable of job results instead of just waiting
         Solves issue where Receive-Job returns NULL even with -Keep parameter
- v7.39: Fixed parameter conflict (removed -Wait from Receive-Job)
- v7.37-v7.38: Attempted various fixes for fast-completing jobs

#>
function Wait-ARIJob {
    Param($JobNames, $JobType, $LoopTime)
    
    # v7.40: Initialize hashtable to store job results as they complete
    $jobResults = @{}

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Jobs Collector.')

    $c = 0
    # ===== PRODUCTION SETTINGS =====
    $TimeoutMinutes = 20  # Total timeout for all jobs (increased from 15 to 20)
    $PerJobTimeoutMinutes = 5  # Per-job timeout (5 minutes for complex resource processing)
    $GetJobTimeout = 10  # Timeout in seconds for Get-Job cmdlet itself
    Write-Host "⏱️  TIMEOUT SETTINGS: Total=$TimeoutMinutes min, Per-Job=$PerJobTimeoutMinutes min, Get-Job=$GetJobTimeout sec" -ForegroundColor Yellow
    # ===== END SETTINGS =====
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
    $lastCompletionCount = 0
    $iterationsSinceProgress = 0
    $maxIterationsWithoutProgress = 20  # v7.4: If no job completes in 20 iterations (~3 min), force timeout
    
    while ($true) {
        $loopIteration++
        Write-Host "🔄 LOOP ITERATION #$loopIteration at $((Get-Date).ToString('HH:mm:ss'))" -ForegroundColor Cyan
        
        # Output visible progress marker every iteration for web interface
        $elapsedSoFar = (Get-Date) - $StartTime
        $minutes = [math]::Floor($elapsedSoFar.TotalMinutes)
        $seconds = [math]::Floor($elapsedSoFar.TotalSeconds % 60)
        Write-Host "⏱️  Elapsed Time: ${minutes}m ${seconds}s" -ForegroundColor Yellow
        
        Write-Host "   Calling Get-Job..." -ForegroundColor Gray
        
        # Protect against Get-Job hanging - use timeout mechanism
        $getJobScriptBlock = { 
            param($JobNames)
            Get-Job -Name $JobNames -ErrorAction SilentlyContinue 
        }
        
        $getJobJob = Start-Job -ScriptBlock $getJobScriptBlock -ArgumentList (,$JobNames)
        $getJobCompleted = Wait-Job -Job $getJobJob -Timeout $GetJobTimeout
        
        if ($null -eq $getJobCompleted) {
            Write-Host "⚠️  WARNING: Get-Job hung for $GetJobTimeout seconds! Force-stopping and retrying..." -ForegroundColor Red
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Get-Job cmdlet hung - stopping after $GetJobTimeout sec timeout")
            Stop-Job -Job $getJobJob -ErrorAction SilentlyContinue
            Remove-Job -Job $getJobJob -Force -ErrorAction SilentlyContinue
            
            # Try one more time with direct call
            Write-Host "   Attempting direct Get-Job call..." -ForegroundColor Gray
            $jb = Get-Job -Name $JobNames -ErrorAction SilentlyContinue
        } else {
            $jb = Receive-Job -Job $getJobJob
            Remove-Job -Job $getJobJob -Force -ErrorAction SilentlyContinue
        }
        
        Write-Host "   Get-Job returned: $($jb.Count) jobs" -ForegroundColor Gray
        
        # If Get-Job returns null or empty, check if jobs completed or disappeared
        if ($null -eq $jb -or $jb.Count -eq 0) {
            Write-Host "   ℹ️  No jobs found in current query" -ForegroundColor Yellow
            # This is normal if all jobs completed quickly - just exit the monitoring loop
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'All jobs completed or cleaned up')
            break
        }
        
        Write-Host "   Filtering jobs by state..." -ForegroundColor Gray
        $runningJobs = $jb | Where-Object { $_.State -eq 'Running' }
        $failedJobs = $jb | Where-Object { $_.State -in @('Failed', 'Stopped', 'Blocked') }
        $completedJobs = $jb | Where-Object { $_.State -eq 'Completed' }
        Write-Host "   Running: $($runningJobs.Count) | Failed: $($failedJobs.Count) | Completed: $($completedJobs.Count)" -ForegroundColor Gray
        
        # v7.40: CRITICAL - Capture output from newly completed jobs IMMEDIATELY
        # PowerShell auto-removes jobs within seconds, must capture before removal
        foreach ($completedJob in $completedJobs) {
            if (-not $jobResults.ContainsKey($completedJob.Name)) {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"⚡ CAPTURING OUTPUT: $($completedJob.Name) just completed")
                try {
                    # Receive job output immediately - can't use -Keep since job will be removed
                    $jobOutput = Receive-Job -Job $completedJob -ErrorAction Stop

                    # v7.40: Standardize result shape to match Build-ARICacheFiles expectations
                    $resultObject = @{
                        Name = $completedJob.Name
                        Output = $jobOutput
                        State = $completedJob.State
                        CapturedAt = Get-Date
                    }
                    $jobResults[$completedJob.Name] = $resultObject
                    
                    # Log what we captured
                    if ($null -eq $jobOutput) {
                        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"⚠️  Job $($completedJob.Name) output is NULL")
                    } else {
                        $outputType = $jobOutput.GetType().Name
                        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"✅ Captured $($completedJob.Name): Type=$outputType")
                        if ($outputType -eq 'Hashtable' -and $jobOutput.Keys) {
                            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"   Keys: $($jobOutput.Keys.Count) - $($jobOutput.Keys -join ', ')")
                        }
                    }
                } catch {
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"❌ ERROR receiving job $($completedJob.Name): $_")
                    $jobResults[$completedJob.Name] = @{
                        Name = $completedJob.Name
                        Output = $null
                        State = $completedJob.State
                        CapturedAt = Get-Date
                        Error = $_.Exception.Message
                    }
                }
            }
        }
        
        # v7.4: Track progress - detect if jobs are completing or all stuck
        if ($completedJobs.Count -gt $lastCompletionCount) {
            Write-Host "   ✅ Progress detected: $($completedJobs.Count - $lastCompletionCount) new completions!" -ForegroundColor Green
            $lastCompletionCount = $completedJobs.Count
            $iterationsSinceProgress = 0
        } else {
            $iterationsSinceProgress++
            if ($iterationsSinceProgress -ge $maxIterationsWithoutProgress) {
                Write-Host "   ⚠️  NO PROGRESS: $iterationsSinceProgress iterations without any job completion!" -ForegroundColor Red
                Write-Warning "STUCK DETECTION: No jobs completed in $iterationsSinceProgress iterations (~$([math]::Round($iterationsSinceProgress * 10 / 60, 1)) minutes). Jobs may be deadlocked."
                Write-Host "   🛑 Force-stopping all running jobs due to suspected deadlock..." -ForegroundColor Red
                foreach ($job in $runningJobs) {
                    Write-Host "      Stopping: $($job.Name)" -ForegroundColor Red
                    $job | Stop-Job -ErrorAction SilentlyContinue
                }
                break
            }
        }
        
        # Check for individual job timeouts - use job NAME as key
        $timedOutJobs = @()
        $currentTime = Get-Date
        
        # Enhanced per-job monitoring with detailed status
        Write-Host "📊 JOB STATUS DETAILS:" -ForegroundColor Cyan
        $jobIndex = 1
        foreach ($job in $runningJobs) {
            if ($jobStartTimes.ContainsKey($job.Name)) {
                $jobRunTime = $currentTime - $jobStartTimes[$job.Name]
                $percentComplete = [math]::Round(($jobRunTime.TotalSeconds / ($PerJobTimeoutMinutes * 60)) * 100, 1)
                $statusIcon = if ($percentComplete -lt 50) { "🟢" } elseif ($percentComplete -lt 80) { "🟡" } else { "🔴" }
                
                Write-Host "   $statusIcon Job $jobIndex/$($runningJobs.Count): $($job.Name)" -ForegroundColor Gray
                Write-Host "      Runtime: $([math]::Floor($jobRunTime.TotalMinutes))m $([math]::Floor($jobRunTime.TotalSeconds % 60))s / $($PerJobTimeoutMinutes)m ($percentComplete%)" -ForegroundColor Gray
                
                # Check for timeout
                if ($jobRunTime -gt $PerJobMaxDuration) {
                    $timedOutJobs += $job
                    Write-Host "      ❌ TIMEOUT EXCEEDED!" -ForegroundColor Red
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"⏰ INDIVIDUAL JOB TIMEOUT: $($job.Name) has been running for $([math]::Round($jobRunTime.TotalMinutes, 1)) minutes")
                    Write-Warning "Job timeout: $($job.Name) exceeded $PerJobTimeoutMinutes minute limit"
                }
                
                $jobIndex++
            } else {
                Write-Host "   ⚠️  $($job.Name) - No start time tracked" -ForegroundColor Yellow
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"WARNING: No start time tracked for job: $($job.Name)")
            }
        }
        
        # Force output on every loop - Write-Host cannot be suppressed (only if jobs are running)
        if ($runningJobs.Count -gt 0 -and $runningJobs.Count -le 5) {
            # Show detailed check only when few jobs remain
            $firstJobName = $runningJobs[0].Name
            if ($jobStartTimes.ContainsKey($firstJobName)) {
                $firstJobRunTime = $currentTime - $jobStartTimes[$firstJobName]
                Write-Host "⏱️ CHECK @ $($currentTime.ToString('HH:mm:ss')): $firstJobName runtime=$([math]::Round($firstJobRunTime.TotalSeconds,0))s / $($PerJobTimeoutMinutes*60)s limit" -ForegroundColor DarkYellow
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
    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Returning $($jobResults.Count) job results")
    
    # Return captured job results to prevent loss from PowerShell auto-removal
    return $jobResults
}
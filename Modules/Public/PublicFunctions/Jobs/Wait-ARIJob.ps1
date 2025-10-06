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
    $TimeoutMinutes = 10
    $PerJobTimeoutMinutes = 5  # Individual job timeout
    $StartTime = Get-Date
    $MaxDuration = New-TimeSpan -Minutes $TimeoutMinutes
    $PerJobMaxDuration = New-TimeSpan -Minutes $PerJobTimeoutMinutes
    
    # Get initial job count and track start times
    $jb = get-job -Name $JobNames -ErrorAction SilentlyContinue
    if ($null -eq $jb -or $jb.Count -eq 0) {
        Write-Warning "CRITICAL: No jobs found with names: $($JobNames -join ', ')"
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"No jobs found to monitor. This may indicate job creation failure.")
        return
    }
    
    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Found $($jb.Count) jobs to monitor. Per-job timeout: $PerJobTimeoutMinutes minutes")
    
    # Track when each job started
    $jobStartTimes = @{}
    foreach ($job in $jb) {
        $jobStartTimes[$job.Id] = if ($job.PSBeginTime) { $job.PSBeginTime } else { Get-Date }
    }

    while ($true) {
        $jb = get-job -Name $JobNames -ErrorAction SilentlyContinue
        
        if ($null -eq $jb) {
            Write-Warning "Jobs disappeared during monitoring!"
            break
        }
        
        $runningJobs = $jb | Where-Object { $_.State -eq 'Running' }
        $failedJobs = $jb | Where-Object { $_.State -in @('Failed', 'Stopped', 'Blocked') }
        
        # Check for individual job timeouts
        $timedOutJobs = @()
        foreach ($job in $runningJobs) {
            if ($jobStartTimes.ContainsKey($job.Id)) {
                $jobRunTime = (Get-Date) - $jobStartTimes[$job.Id]
                if ($jobRunTime -gt $PerJobMaxDuration) {
                    $timedOutJobs += $job
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"INDIVIDUAL JOB TIMEOUT: $($job.Name) has been running for $([math]::Round($jobRunTime.TotalMinutes, 1)) minutes")
                }
            }
        }
        
        # Stop timed out jobs
        if ($timedOutJobs.Count -gt 0) {
            Write-Warning "Stopping $($timedOutJobs.Count) jobs that exceeded $PerJobTimeoutMinutes minute timeout"
            foreach ($job in $timedOutJobs) {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Stopping stuck job: $($job.Name)")
                $job | Stop-Job -ErrorAction SilentlyContinue
            }
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
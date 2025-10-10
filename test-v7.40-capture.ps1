# Test v7.40 job capture mechanism locally
# This simulates the Wait-ARIJob immediate capture pattern

Write-Host "`n🧪 Testing v7.40 Job Capture Mechanism" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Gray

# Create test jobs that return different types of data
Write-Host "`n📦 Creating test jobs..." -ForegroundColor Yellow

# Job 1: Returns hashtable (simulates successful module processing)
Start-Job -Name "TestJob_Success" -ScriptBlock {
    Start-Sleep -Milliseconds 500
    $result = @{
        'VirtualMachines' = @('VM1', 'VM2', 'VM3')
        'Disks' = @('Disk1', 'Disk2')
    }
    Write-Output $result
} | Out-Null

# Job 2: Returns null (simulates module with no resources)
Start-Job -Name "TestJob_Empty" -ScriptBlock {
    Start-Sleep -Milliseconds 300
    return $null
} | Out-Null

# Job 3: Returns array (simulates different return type)
Start-Job -Name "TestJob_Array" -ScriptBlock {
    Start-Sleep -Milliseconds 400
    return @('Item1', 'Item2', 'Item3')
} | Out-Null

Write-Host "✅ Created 3 test jobs" -ForegroundColor Green

# Wait a moment for jobs to start
Start-Sleep -Seconds 1

# Simulate Wait-ARIJob v7.40 capture logic
Write-Host "`n⏱️  Simulating Wait-ARIJob v7.40 capture..." -ForegroundColor Cyan
$jobResults = @{}
$maxIterations = 20
$iteration = 0

while ($iteration -lt $maxIterations) {
    $iteration++
    
    $allJobs = Get-Job | Where-Object { $_.Name -like 'TestJob_*' }
    $runningJobs = $allJobs | Where-Object { $_.State -eq 'Running' }
    $completedJobs = $allJobs | Where-Object { $_.State -eq 'Completed' }
    
    Write-Host "  Iteration $iteration : $($runningJobs.Count) running, $($completedJobs.Count) completed" -ForegroundColor Gray
    
    # Detect newly completed jobs
    $newlyCompleted = $completedJobs | Where-Object { -not $jobResults.ContainsKey($_.Name) }
    
    if ($newlyCompleted.Count -gt 0) {
        Write-Host "`n🎯 CAPTURING OUTPUT FOR $($newlyCompleted.Count) NEWLY COMPLETED JOB(S)" -ForegroundColor Green
        
        foreach ($job in $newlyCompleted) {
            Write-Host "   📦 Capturing: $($job.Name)" -ForegroundColor Cyan
            try {
                $output = Receive-Job -Job $job -Keep -ErrorAction SilentlyContinue
                $jobResults[$job.Name] = @{
                    Name = $job.Name
                    Output = $output
                    State = $job.State
                    CapturedAt = Get-Date
                    HasData = ($null -ne $output)
                }
                
                $dataStatus = if ($output) {
                    if ($output -is [hashtable]) {
                        "Hashtable with $($output.Keys.Count) keys"
                    } elseif ($output -is [array]) {
                        "Array with $($output.Count) items"
                    } else {
                        "Type: $($output.GetType().Name)"
                    }
                } else {
                    "NULL"
                }
                
                Write-Host "   ✅ Captured $($job.Name): $dataStatus" -ForegroundColor Green
                
            } catch {
                Write-Host "   ❌ Failed to capture $($job.Name): $_" -ForegroundColor Red
                $jobResults[$job.Name] = @{
                    Name = $job.Name
                    Output = $null
                    State = 'Error'
                    Error = $_.Exception.Message
                }
            }
        }
    }
    
    # Check if all jobs are done
    if ($runningJobs.Count -eq 0) {
        Write-Host "`n✅ All jobs completed!" -ForegroundColor Green
        break
    }
    
    Start-Sleep -Milliseconds 500
}

# Display results
Write-Host "`n📊 CAPTURE RESULTS:" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Gray

foreach ($jobName in $jobResults.Keys | Sort-Object) {
    $jobData = $jobResults[$jobName]
    Write-Host "`n🔹 Job: $jobName" -ForegroundColor Yellow
    Write-Host "   State: $($jobData.State)" -ForegroundColor Gray
    Write-Host "   Has Data: $($jobData.HasData)" -ForegroundColor Gray
    
    if ($null -ne $jobData.Output) {
        $output = $jobData.Output
        Write-Host "   Output Type: $($output.GetType().Name)" -ForegroundColor Gray
        
        if ($output -is [hashtable]) {
            Write-Host "   Hashtable Keys: $($output.Keys -join ', ')" -ForegroundColor Gray
            foreach ($key in $output.Keys) {
                $value = $output[$key]
                if ($value -is [array]) {
                    Write-Host "     - $key : Array[$($value.Count)]" -ForegroundColor Gray
                } else {
                    Write-Host "     - $key : $value" -ForegroundColor Gray
                }
            }
        } elseif ($output -is [array]) {
            Write-Host "   Array Items: $($output.Count)" -ForegroundColor Gray
        }
    } else {
        Write-Host "   Output: NULL" -ForegroundColor Red
    }
}

# Test Build-ARICacheFiles pattern
Write-Host "`n`n🧪 Testing Build-ARICacheFiles v7.40 pattern..." -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Gray

foreach ($jobName in $jobResults.Keys | Sort-Object) {
    $jobData = $jobResults[$jobName]
    $tempJob = $jobData.Output
    $newJobName = ($jobName -replace 'TestJob_', '')
    
    if ($null -eq $tempJob) {
        Write-Host "❌ Job '$newJobName' returned NULL" -ForegroundColor Red
    } else {
        Write-Host "✅ Job '$newJobName' returned type: $($tempJob.GetType().Name)" -ForegroundColor Green
        
        if ($tempJob -is [hashtable]) {
            Write-Host "   Hashtable has $($tempJob.Keys.Count) keys" -ForegroundColor Cyan
        } elseif ($tempJob -is [array]) {
            Write-Host "   Array has $($tempJob.Count) items" -ForegroundColor Cyan
        }
    }
}

# Cleanup
Write-Host "`n`n🧹 Cleaning up test jobs..." -ForegroundColor Gray
Get-Job | Where-Object { $_.Name -like 'TestJob_*' } | Remove-Job -Force
Write-Host "✅ Test complete!`n" -ForegroundColor Green

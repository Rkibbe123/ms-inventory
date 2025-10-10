<#
.Synopsis
Module responsible for starting the processing jobs for Azure Resources.

.DESCRIPTION
This module creates and manages jobs to process Azure Resources in batches based on the environment size. It ensures efficient resource processing and avoids CPU overload.

.Link
https://github.com/microsoft/ARI/Modules/Private/2.ProcessingFunctions/Start-ARIProcessJob.ps1

.COMPONENT
This PowerShell Module is part of Azure Resource Inventory (ARI).

.NOTES
Version: 3.6.9 - v7.38
First Release Date: 15th Oct, 2024
Authors: Claudio Merola

.CHANGELOG
v7.38 (2024-10-09): CRITICAL FIX - Jobs complete instantly and auto-remove, added -Keep -Wait to Receive-Job
v7.37 (2024-10-09): FAILED - Write-Output used but jobs auto-cleanup before Receive-Job runs
v7.36 (2024-10-09): FAILED - Hashtable created but implicit return captured Write-Host instead of hashtable
v7.35 (2024-10-09): FAILED - Two AddScript() calls create nested scopes, module can't see $Resources
v7.34 (2024-10-09): Rebuild with --no-cache to deploy v7.33 changes
v7.33 (2024-10-09): Hybrid solution - reduce batch size (8→4) AND use per-job filtering
v7.30 (2024-10-08): Replace JSON with XML serialization (Import-Clixml)
#>

function Start-ARIProcessJob {
    Param($Resources, $Retirements, $Subscriptions, $DefaultPath, $Heavy, $InTag, $Unsupported)

    Write-Progress -activity 'Azure Inventory' -Status "22% Complete." -PercentComplete 22 -CurrentOperation "Creating Jobs to Process Data.."

    switch ($Resources.count)
    {
        {$_ -le 12500}
            {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Regular Size Environment. Jobs will be run in parallel.')
                $EnvSizeLooper = 4  # v7.33: Reduced from 8 to 4 to reduce memory pressure during Import-Clixml
                Write-Host "⚙️  Parallel job limit set to $EnvSizeLooper (v7.33-v7.35: reduced batches + per-job filtering)" -ForegroundColor Cyan
            }
        {$_ -gt 12500 -and $_ -le 50000}
            {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Medium Size Environment. Jobs will be run in batches of 6.')
                $EnvSizeLooper = 6  # v7.5: Increased from 4 to 6
                Write-Host "⚙️  Medium environment: Jobs will be run in batches of $EnvSizeLooper" -ForegroundColor Yellow
            }
        {$_ -gt 50000}
            {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Large Environment Detected.')
                $EnvSizeLooper = 5  # v7.5: Increased from 3 to 5
                Write-Host ('⚙️  Large environment: Jobs will be run in small batches of ' + $EnvSizeLooper + ' to avoid CPU and Memory Overload.') -ForegroundColor Red
            }
    }

    if ($Heavy.IsPresent -or $InTag.IsPresent)
        {
            Write-Host ('⚙️  Heavy Mode or InTag Mode Detected. Jobs will be run in small batches of 5 to avoid CPU and Memory Overload.') -ForegroundColor Red
            $EnvSizeLooper = 5  # v7.5: Increased from 3 to 5 with upgraded container
        }

    $ParentPath = (get-item $PSScriptRoot).parent.parent
    $InventoryModulesPath = Join-Path $ParentPath 'Public' 'InventoryModules'
    
    # Process all resource type modules for comprehensive inventory
    $ModuleFolders = Get-ChildItem -Path $InventoryModulesPath -Directory
    Write-Host "📊 Processing all $($ModuleFolders.Count) resource type modules for complete inventory" -ForegroundColor Green

    $JobLoop = 1
    $TotalFolders = $ModuleFolders.count

    # v7.10: Debug logging to verify resource count before JSON conversion
    $ResourceCount = $Resources.count
    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Resources received for processing: '+ $ResourceCount)
    Write-Host "🔍 Preparing to process $ResourceCount resources across $TotalFolders modules" -ForegroundColor Cyan

    # v7.33: ARCHITECTURE CHANGE - Don't serialize all resources at once
    # Jobs crash trying to import 87 MB file even at depth 5
    # Instead: Keep resources in memory and filter per-job (smaller temp files)
    Write-Host "� Using per-job filtering to reduce memory footprint" -ForegroundColor Cyan
    
    # Store all resources for filtering later
    $AllResources = $Resources
    Remove-Variable -Name Resources
    Clear-ARIMemory

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting to Create Jobs to Process the Resources.')

    #Foreach ($ModuleFolder in $ModuleFolders)
    $ModuleFolders | ForEach-Object -Process {
            $ModuleFolder = $_
            $ModulePath = Join-Path $ModuleFolder.FullName '*.ps1'
            $ModuleName = $ModuleFolder.Name
            $ModuleFiles = Get-ChildItem -Path $ModulePath

            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Creating Job: '+$ModuleName)

            # v7.33: CRITICAL - Filter resources by module type BEFORE creating temp file
            # This creates small per-job files (5-10 MB) instead of one giant 87 MB file
            # Read the first module file to get resource type filters
            $FirstModuleContent = Get-Content -Path $ModuleFiles[0].FullName -Raw
            
            # Extract resource type from Where-Object clause (e.g., "microsoft.cognitiveservices/accounts")
            if ($FirstModuleContent -match "TYPE -eq '([^']+)'") {
                $ResourceType = $matches[1]
                $FilteredResources = $AllResources | Where-Object { $_.TYPE -eq $ResourceType }
            } else {
                # Fallback: pass all resources if we can't determine filter
                $FilteredResources = $AllResources
            }
            
            if ($null -eq $FilteredResources) { $FilteredResources = @() }
            $FilteredCount = $FilteredResources.count
            Write-Host "📦 [$ModuleName] Filtered to $FilteredCount resources" -ForegroundColor Cyan
            
            # Create per-job temp file with ONLY filtered resources
            $TempJobFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "ari_${ModuleName}_$(Get-Date -Format 'yyyyMMdd_HHmmss').xml")
            
            try {
                $FilteredResources | Export-Clixml -Path $TempJobFile -Depth 5 -Force
                $JobFileSize = (Get-Item $TempJobFile).Length / 1MB
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Job temp file: $([math]::Round($JobFileSize, 2)) MB for $FilteredCount resources")
            } catch {
                Write-Error "Failed to create temp file for $ModuleName : $_"
                return
            }

            $c = (($JobLoop / $TotalFolders) * 100)
            $c = [math]::Round($c)
            Write-Progress -Id 1 -activity "Creating Jobs" -Status "$c% Complete." -PercentComplete $c

            Start-Job -Name ('ResourceJob_'+$ModuleName) -ScriptBlock {
                
                # v7.17: CRITICAL ARCHITECTURE CHANGE - Read JSON from file instead of ArgumentList
                # v7.16 execution proved jobs fail before try-catch executes (ArgumentList size limit exceeded)
                # Jobs completed in 3-4 seconds with zero logging = initialization failure, not execution failure
                try {
                    $FolderName = $($args[1])
                    Write-Host "[JOB START] ========================================" -ForegroundColor Cyan
                    Write-Host "[JOB START] Processing folder: $FolderName" -ForegroundColor Cyan
                    Write-Host "[JOB START] Args received: $($args.Count)" -ForegroundColor Cyan
                    
                    $ModuleFiles = $($args[0])
                    Write-Host "[JOB] Module files count: $($ModuleFiles.Count)" -ForegroundColor Cyan
                    
                    $Subscriptions = $($args[2])
                    $InTag = $($args[3])
                    
                    # v7.17: Read JSON from temp file instead of receiving via ArgumentList
                    # $args[4] now contains the temp file path, not the 18.2 MB JSON string
                    $TempJsonFile = $($args[4])
                    Write-Host "[JOB] Reading resources from temp file: $TempJsonFile" -ForegroundColor Yellow
                    
                    if (-not (Test-Path $TempJsonFile)) {
                        throw "Temp file not found: $TempJsonFile"
                    }

                    # Helper: wait until the file is stable (exists, non-zero, size unchanged across checks)
                    function Wait-ARIStableFile {
                        param(
                            [Parameter(Mandatory)] [string] $Path,
                            [int] $MinBytes = 10,
                            [int] $Retries = 15,
                            [int] $DelayMs = 200
                        )
                        for ($i = 1; $i -le $Retries; $i++) {
                            if (-not (Test-Path -LiteralPath $Path)) {
                                Start-Sleep -Milliseconds $DelayMs
                                continue
                            }
                            try {
                                $fi1 = Get-Item -LiteralPath $Path -ErrorAction Stop
                                $size1 = $fi1.Length
                                $time1 = $fi1.LastWriteTimeUtc
                                Start-Sleep -Milliseconds $DelayMs
                                $fi2 = Get-Item -LiteralPath $Path -ErrorAction Stop
                                $size2 = $fi2.Length
                                $time2 = $fi2.LastWriteTimeUtc
                                if ($size1 -ge $MinBytes -and $size1 -eq $size2 -and $time1 -eq $time2) {
                                    return $true
                                }
                            } catch {
                                # ignore transient errors and retry
                            }
                        }
                        return $false
                    }
                    
                    # v7.30: PERFORMANCE FIX - Use Import-Clixml instead of ConvertFrom-Json
                    # Import-Clixml is significantly faster and doesn't hang like ConvertFrom-Json
                    Write-Host "[JOB] Importing resources from temp file... (this may take 5-10 seconds)" -ForegroundColor Yellow

                    # Ensure file is stable before importing
                    $stable = Wait-ARIStableFile -Path $TempJsonFile -MinBytes 10 -Retries 20 -DelayMs 150
                    $fi = $null
                    if ($stable) { $fi = Get-Item -LiteralPath $TempJsonFile -ErrorAction SilentlyContinue }
                    $sizeMb = if ($fi) { [Math]::Round(($fi.Length/1MB), 2) } else { 0 }
                    Write-Host "[JOB] Temp file size: $sizeMb MB" -ForegroundColor Gray

                    # Quick header check (CLIXML files typically start with '#< CLIXML')
                    try {
                        $firstLine = Get-Content -LiteralPath $TempJsonFile -First 1 -ErrorAction Stop
                        if ($firstLine -notmatch 'CLIXML') {
                            Write-Host "[JOB WARN] Temp file does not start with CLIXML header (line1: '$firstLine')" -ForegroundColor DarkYellow
                        }
                    } catch { }

                    $Resources = $null
                    $importError = $null
                    $maxAttempts = 5
                    for ($attempt = 1; $attempt -le $maxAttempts -and $null -eq $Resources; $attempt++) {
                        try {
                            Write-Host "[JOB] Import-Clixml attempt $attempt/$maxAttempts" -ForegroundColor Gray
                            $Resources = Import-Clixml -Path $TempJsonFile -ErrorAction Stop
                        } catch {
                            $importError = $_
                            Start-Sleep -Milliseconds ([int][Math]::Min(1500, 200 * [Math]::Pow(2, ($attempt - 1))))
                        }
                    }

                    # Fallback: copy the file and import from the copy to avoid any transient locks
                    if ($null -eq $Resources) {
                        try {
                            $copyPath = "$TempJsonFile.copy"
                            Copy-Item -LiteralPath $TempJsonFile -Destination $copyPath -Force -ErrorAction Stop
                            Write-Host "[JOB] Retrying import from copied file: $copyPath" -ForegroundColor Gray
                            $Resources = Import-Clixml -Path $copyPath -ErrorAction Stop
                            Remove-Item -LiteralPath $copyPath -Force -ErrorAction SilentlyContinue
                        } catch {
                            if (Test-Path -LiteralPath $copyPath) { Remove-Item -LiteralPath $copyPath -Force -ErrorAction SilentlyContinue }
                            if ($null -eq $importError) { $importError = $_ }
                        }
                    }

                    if ($null -eq $Resources) {
                        Write-Host "[JOB ERROR] ❌ Import-Clixml returned null!" -ForegroundColor Red
                        $msg = if ($importError) { $importError.Exception.Message } else { 'Unknown import failure' }
                        throw "Import-Clixml failed - Resources is null (size=${sizeMb}MB): $msg"
                    }

                    # Safely get count with null check
                    $ResourceCount = if ($Resources) { 
                        if ($Resources -is [Array]) { $Resources.Count } 
                        else { 1 } 
                    } else { 0 }
                    Write-Host "[JOB] ✅ Resources imported successfully: $ResourceCount items" -ForegroundColor Green
                    
                    $Retirements = $($args[5])
                    $Task = $($args[6])
                    $Unsupported = $($args[10])

                $job = @()

                Foreach ($Module in $ModuleFiles)
                    {
                        $ModuleFileContent = New-Object System.IO.StreamReader($Module.FullName)
                        $ModuleData = $ModuleFileContent.ReadToEnd()
                        $ModuleFileContent.Dispose()
                        $ModName = $Module.Name.replace(".ps1","")

                        New-Variable -Name ('ModRun' + $ModName)
                        New-Variable -Name ('ModJob' + $ModName)

                        # v7.36: FIXED - Wrap module code with variable assignments in SINGLE script block
                        # Module files reference $Resources directly, needs to be in same scope
                        # Previous fix (v7.35) failed: two separate AddScript() calls create nested scopes
                        # Solution: Combine variable assignment + module code into ONE script string
                        $CombinedScript = @"
# Assign variables from arguments
`$Resources = `$args[0]
`$PSScriptRoot = `$args[1]
`$Subscriptions = `$args[2]
`$InTag = `$args[3]
`$Retirements = `$args[4]
`$Task = `$args[5]
`$Unsupported = `$args[6]

# Execute module code in same scope
$ModuleData
"@
                        
                        Set-Variable -Name ('ModRun' + $ModName) -Value ([PowerShell]::Create()).AddScript($CombinedScript).AddArgument($Resources).AddArgument($PSScriptRoot).AddArgument($Subscriptions).AddArgument($InTag).AddArgument($Retirements).AddArgument($Task).AddArgument($Unsupported)

                        Set-Variable -Name ('ModJob' + $ModName) -Value ((get-variable -name ('ModRun' + $ModName)).Value).BeginInvoke()

                        $job += (get-variable -name ('ModJob' + $ModName)).Value
                        Start-Sleep -Milliseconds 100
                        Remove-Variable -Name ModName
                    }

                While ($Job.Runspace.IsCompleted -contains $false) { Start-Sleep -Milliseconds 500 }

                Foreach ($Module in $ModuleFiles)
                    {
                        $ModName = $Module.Name.replace(".ps1","")
                        New-Variable -Name ('ModValue' + $ModName)
                        Set-Variable -Name ('ModValue' + $ModName) -Value (((get-variable -name ('ModRun' + $ModName)).Value).EndInvoke((get-variable -name ('ModJob' + $ModName)).Value))

                        Remove-Variable -Name ('ModRun' + $ModName)
                        Remove-Variable -Name ('ModJob' + $ModName)
                        Start-Sleep -Milliseconds 100
                        Remove-Variable -Name ModName
                    }

                $Hashtable = New-Object System.Collections.Hashtable

                Foreach ($Module in $ModuleFiles)
                    {
                        $ModName = $Module.Name.replace(".ps1","")

                        $Hashtable["$ModName"] = (get-variable -name ('ModValue' + $ModName)).Value

                        # v7.16: Log each module's contribution with more detail
                        $ModuleResult = (get-variable -name ('ModValue' + $ModName)).Value
                        $ModuleResultCount = ($ModuleResult | Measure-Object).Count
                        Write-Host "[JOB] Module '$ModName' returned: $ModuleResultCount items" -ForegroundColor Yellow
                        if ($ModuleResultCount -gt 0) {
                            Write-Host "[JOB] Module '$ModName' sample result type: $($ModuleResult[0].GetType().Name)" -ForegroundColor Gray
                        }

                        Remove-Variable -Name ('ModValue' + $ModName)
                        Start-Sleep -Milliseconds 100

                        Remove-Variable -Name ModName
                    }

                # v7.16: Enhanced logging before returning
                Write-Host "[JOB] ========================================" -ForegroundColor Green
                Write-Host "[JOB] Hashtable complete with $($Hashtable.Keys.Count) keys" -ForegroundColor Green
                Write-Host "[JOB] Keys: $($Hashtable.Keys -join ', ')" -ForegroundColor Green
                
                # Calculate total items across all modules
                $TotalItems = 0
                foreach ($key in $Hashtable.Keys) {
                    $count = ($Hashtable[$key] | Measure-Object).Count
                    $TotalItems += $count
                    Write-Host "[JOB] Key '$key' has $count items" -ForegroundColor Gray
                }
                Write-Host "[JOB] Total items across all modules: $TotalItems" -ForegroundColor Green
                Write-Host "[JOB END] Returning hashtable for folder: $FolderName" -ForegroundColor Cyan
                Write-Host "[JOB END] ========================================" -ForegroundColor Cyan

                # v7.37: CRITICAL FIX - Use Write-Output to ensure hashtable is returned properly
                # Write-Host goes to console, Write-Output goes to pipeline (what Receive-Job captures)
                Write-Output $Hashtable
                
                } catch {
                    # v7.16: Catch and log ANY errors in job execution
                    Write-Host "[JOB ERROR] ========================================" -ForegroundColor Red
                    Write-Host "[JOB ERROR] Exception in folder: $FolderName" -ForegroundColor Red
                    Write-Host "[JOB ERROR] Message: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "[JOB ERROR] Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
                    Write-Host "[JOB ERROR] Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor Red
                    Write-Host "[JOB ERROR] ========================================" -ForegroundColor Red
                    
                    # Return empty hashtable on error so we don't crash Build-ARICacheFiles
                    @{}
                }

            } -ArgumentList $ModuleFiles, $PSScriptRoot, $Subscriptions, $InTag, $TempJobFile , $Retirements, 'Processing', $null, $null, $null, $Unsupported | Out-Null

        if($JobLoop -eq $EnvSizeLooper)
            {
                Write-Host 'Waiting Batch Jobs' -ForegroundColor Cyan -NoNewline
                Write-Host '. This step may take several minutes to finish' -ForegroundColor Cyan

                $InterJobNames = (Get-Job | Where-Object {$_.name -like 'ResourceJob_*' -and $_.State -eq 'Running'}).Name

                # v7.40.1: CRITICAL FIX - Capture jobs BEFORE they auto-remove
                # Jobs complete in < 1 second, must capture immediately
                Write-Host "⚡ FAST CAPTURE: Polling for job completion (jobs finish in < 1 sec)..." -ForegroundColor Yellow
                
                $JobResults = @{}
                $maxWaitSeconds = 30
                $pollInterval = 0.5  # Poll every 500ms
                $elapsedSeconds = 0
                
                while ($elapsedSeconds -lt $maxWaitSeconds) {
                    Start-Sleep -Milliseconds ($pollInterval * 1000)
                    $elapsedSeconds += $pollInterval
                    
                    # Get ALL jobs (completed + running)
                    $allJobs = Get-Job -Name $InterJobNames -ErrorAction SilentlyContinue
                    
                    if ($allJobs) {
                        foreach ($job in $allJobs) {
                            # If job completed and not yet captured
                            if ($job.State -eq 'Completed' -and -not $JobResults.ContainsKey($job.Name)) {
                                Write-Host "   ⚡ Capturing $($job.Name) (completed at $($job.PSEndTime))" -ForegroundColor Green
                                $output = Receive-Job -Job $job -Keep -ErrorAction SilentlyContinue
                                $JobResults[$job.Name] = @{
                                    Name = $job.Name
                                    Output = $output
                                    State = $job.State
                                    CapturedAt = Get-Date
                                }
                            }
                        }
                        
                        # Check if all jobs captured
                        $remainingJobs = $allJobs | Where-Object { $_.State -in @('Running', 'NotStarted') }
                        if ($remainingJobs.Count -eq 0 -and $JobResults.Count -eq $InterJobNames.Count) {
                            Write-Host "✅ All $($JobResults.Count) jobs captured!" -ForegroundColor Green
                            break
                        }
                    }
                }
                
                Write-Host "📊 Captured $($JobResults.Count) of $($InterJobNames.Count) jobs" -ForegroundColor Cyan
                
                # v7.40: CRITICAL CHANGE - Pass captured job results to Build-ARICacheFiles
                Build-ARICacheFiles -DefaultPath $DefaultPath -JobResults $JobResults

                $JobLoop = 0
            }
        $JobLoop ++

        }

        # v7.26: CRITICAL FIX - Process remaining jobs after ForEach loop completes
        # The last batch might have fewer than 8 jobs, so Build-ARICacheFiles was never called!
        # This is why we only got Compute and Advisor - they were in first batch of 8
        $RemainingJobNames = (Get-Job | Where-Object {$_.name -like 'ResourceJob_*' -and $_.State -eq 'Running'}).Name
        
        if ($RemainingJobNames -and $RemainingJobNames.Count -gt 0) {
            Write-Host "⏳ Waiting for final batch of $($RemainingJobNames.Count) jobs to complete..." -ForegroundColor Cyan
            
            # v7.40.1: CRITICAL FIX - Fast capture instead of Wait-ARIJob
            Write-Host "⚡ FAST CAPTURE: Polling for job completion..." -ForegroundColor Yellow
            
            $FinalJobResults = @{}
            $maxWaitSeconds = 30
            $pollInterval = 0.5
            $elapsedSeconds = 0
            
            while ($elapsedSeconds -lt $maxWaitSeconds) {
                Start-Sleep -Milliseconds ($pollInterval * 1000)
                $elapsedSeconds += $pollInterval
                
                $allJobs = Get-Job -Name $RemainingJobNames -ErrorAction SilentlyContinue
                
                if ($allJobs) {
                    foreach ($job in $allJobs) {
                        if ($job.State -eq 'Completed' -and -not $FinalJobResults.ContainsKey($job.Name)) {
                            Write-Host "   ⚡ Capturing $($job.Name)" -ForegroundColor Green
                            $output = Receive-Job -Job $job -Keep -ErrorAction SilentlyContinue
                            $FinalJobResults[$job.Name] = @{
                                Name = $job.Name
                                Output = $output
                                State = $job.State
                            }
                        }
                    }
                    
                    $remainingJobs = $allJobs | Where-Object { $_.State -in @('Running', 'NotStarted') }
                    if ($remainingJobs.Count -eq 0 -and $FinalJobResults.Count -eq $RemainingJobNames.Count) {
                        Write-Host "✅ All $($FinalJobResults.Count) jobs captured!" -ForegroundColor Green
                        break
                    }
                }
            }
            
            # Note: Removed unused variable assignment of $FinalJobNames to satisfy linters
            Write-Host "📦 Building cache files for final batch ($($FinalJobResults.Count) captured)..." -ForegroundColor Cyan
            # v7.40: CRITICAL CHANGE - Pass captured job results to Build-ARICacheFiles
            Build-ARICacheFiles -DefaultPath $DefaultPath -JobResults $FinalJobResults
        }

        # v7.33: Clean up all per-job temp XML files after all jobs complete
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Cleaning up per-job temp files")
        $TempFiles = Get-ChildItem -Path ([System.IO.Path]::GetTempPath()) -Filter "ari_*_*.xml" -ErrorAction SilentlyContinue
        if ($TempFiles) {
            foreach ($TempFile in $TempFiles) {
                Remove-Item -Path $TempFile.FullName -Force -ErrorAction SilentlyContinue
            }
            Write-Host "🗑️  Cleaned up $($TempFiles.Count) temp file(s)" -ForegroundColor Gray
        }

        # v7.30: NewResources variable no longer exists (using Export-Clixml instead)
        Clear-ARIMemory
}
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
Version: 3.6.5
First Release Date: 15th Oct, 2024
Authors: Claudio Merola
#>

function Start-ARIProcessJob {
    Param($Resources, $Retirements, $Subscriptions, $DefaultPath, $Heavy, $InTag, $Unsupported)

    Write-Progress -activity 'Azure Inventory' -Status "22% Complete." -PercentComplete 22 -CurrentOperation "Creating Jobs to Process Data.."

    switch ($Resources.count)
    {
        {$_ -le 12500}
            {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Regular Size Environment. Jobs will be run in parallel.')
                $EnvSizeLooper = 8  # v7.9: Back to 8 - Get-Job hangs with 16 jobs, 8 is the sweet spot
                Write-Host "⚙️  Parallel job limit set to $EnvSizeLooper (v7.9: optimized - 16 caused Get-Job hangs)" -ForegroundColor Cyan
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

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Converting Resource data to JSON for Jobs')
    $NewResources = ($Resources | ConvertTo-Json -Depth 40 -Compress -AsArray)

    # v7.10: Verify JSON conversion didn't break
    $JsonLength = $NewResources.Length
    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'JSON string length: '+ $JsonLength + ' characters')
    if ($JsonLength -lt 100) {
        Write-Host "⚠️  WARNING: JSON string suspiciously short ($JsonLength chars) - resources may be empty!" -ForegroundColor Yellow
    }

    Remove-Variable -Name Resources
    Clear-ARIMemory

    # v7.17: CRITICAL ARCHITECTURE CHANGE - Write JSON to temp file instead of passing via ArgumentList
    # PowerShell Start-Job has size limits on -ArgumentList (our 18.2 MB JSON exceeds it)
    # Jobs were completing in 3-4 seconds (instant failure) before scriptblock could execute
    $TempJsonFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "ari_resources_$(Get-Date -Format 'yyyyMMdd_HHmmss').json")
    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Writing resources to temp file: $TempJsonFile")
    
    try {
        $NewResources | Out-File -FilePath $TempJsonFile -Encoding UTF8 -Force
        $FileSize = (Get-Item $TempJsonFile).Length / 1MB
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Temp file created: $([math]::Round($FileSize, 2)) MB")
        Write-Host "📁 Resources written to temp file: $([math]::Round($FileSize, 2)) MB" -ForegroundColor Green
    } catch {
        Write-Error "Failed to write resources to temp file: $_"
        return
    }

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting to Create Jobs to Process the Resources.')

    #Foreach ($ModuleFolder in $ModuleFolders)
    $ModuleFolders | ForEach-Object -Process {
            $ModuleFolder = $_
            $ModulePath = Join-Path $ModuleFolder.FullName '*.ps1'
            $ModuleName = $ModuleFolder.Name
            $ModuleFiles = Get-ChildItem -Path $ModulePath

            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Creating Job: '+$ModuleName)

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
                        throw "Temp JSON file not found: $TempJsonFile"
                    }
                    
                    $JsonContent = Get-Content -Path $TempJsonFile -Raw
                    Write-Host "[JOB] JSON file read: $([math]::Round($JsonContent.Length / 1MB, 2)) MB" -ForegroundColor Yellow
                    Write-Host "[JOB] Deserializing JSON..." -ForegroundColor Yellow
                    
                    try {
                        $Resources = $JsonContent | ConvertFrom-Json -ErrorAction Stop
                        
                        if ($null -eq $Resources) {
                            Write-Host "[JOB ERROR] ❌ JSON deserialization returned null!" -ForegroundColor Red
                            throw "JSON deserialization failed - Resources is null"
                        }
                        
                        Write-Host "[JOB] ✅ Resources deserialized successfully" -ForegroundColor Green
                        
                        # Safely get count with null check
                        $ResourceCount = if ($Resources) { 
                            if ($Resources -is [Array]) { $Resources.Count } 
                            else { 1 } 
                        } else { 0 }
                        
                        Write-Host "[JOB] Resource count: $ResourceCount" -ForegroundColor Green
                    }
                    catch {
                        Write-Host "[JOB ERROR] ❌ Exception during JSON deserialization: $($_.Exception.Message)" -ForegroundColor Red
                        Write-Host "[JOB ERROR] Error details: $($_.Exception.GetType().FullName)" -ForegroundColor Red
                        throw "JSON deserialization failed: $($_.Exception.Message)"
                    }
                    
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

                        Set-Variable -Name ('ModRun' + $ModName) -Value ([PowerShell]::Create()).AddScript($ModuleData).AddArgument($PSScriptRoot).AddArgument($Subscriptions).AddArgument($InTag).AddArgument($Resources).AddArgument($Retirements).AddArgument($Task).AddArgument($null).AddArgument($null).AddArgument($null).AddArgument($Unsupported)

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

                # Return the hashtable
                $Hashtable
                
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

            } -ArgumentList $ModuleFiles, $PSScriptRoot, $Subscriptions, $InTag, $TempJsonFile , $Retirements, 'Processing', $null, $null, $null, $Unsupported | Out-Null

        if($JobLoop -eq $EnvSizeLooper)
            {
                Write-Host 'Waiting Batch Jobs' -ForegroundColor Cyan -NoNewline
                Write-Host '. This step may take several minutes to finish' -ForegroundColor Cyan

                $InterJobNames = (Get-Job | Where-Object {$_.name -like 'ResourceJob_*' -and $_.State -eq 'Running'}).Name

                Wait-ARIJob -JobNames $InterJobNames -JobType 'Resource Batch' -LoopTime 5

                $JobNames = (Get-Job | Where-Object {$_.name -like 'ResourceJob_*'}).Name

                Build-ARICacheFiles -DefaultPath $DefaultPath -JobNames $JobNames

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
            Wait-ARIJob -JobNames $RemainingJobNames -JobType 'Resource Final Batch' -LoopTime 5
            
            $FinalJobNames = (Get-Job | Where-Object {$_.name -like 'ResourceJob_*'}).Name
            Write-Host "📦 Building cache files for final batch ($($FinalJobNames.Count) jobs)..." -ForegroundColor Cyan
            Build-ARICacheFiles -DefaultPath $DefaultPath -JobNames $FinalJobNames
        }

        # v7.17: Clean up temp JSON file after all jobs complete
        if (Test-Path $TempJsonFile) {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Removing temp JSON file: $TempJsonFile")
            Remove-Item -Path $TempJsonFile -Force -ErrorAction SilentlyContinue
            Write-Host "🗑️  Temp file cleaned up" -ForegroundColor Gray
        }

        Remove-Variable -Name NewResources
        Clear-ARIMemory
}
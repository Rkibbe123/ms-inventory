<#
.Synopsis
Module responsible for creating the local cache files for the report.

.DESCRIPTION
This module receives the job names for the Azure Resources that were processed previously and creates the local cache files that will be used to build the Excel report.

.Link
https://github.com/microsoft/ARI/Modules/Private/2.ProcessingFunctions/Build-ARICacheFiles.ps1

.COMPONENT
This PowerShell Module is part of Azure Resource Inventory (ARI).

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola
#>

function Build-ARICacheFiles {
    Param($DefaultPath, $JobNames)

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Checking Cache Folder.')

    # v7.27: CRITICAL FIX - Check $null FIRST before accessing .Count property
    # Accessing .Count on $null throws "cannot call method on null-valued expression"
    if ($null -eq $JobNames -or @($JobNames).Count -eq 0) {
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'⚠️  ERROR: JobNames is null or empty! No jobs to process.')
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'This usually means jobs completed and were removed before we could receive their results.')
        return
    }

    $Lops = @($JobNames).count
    $Counter = 0

    Foreach ($Job in $JobNames)
        {
            $c = (($Counter / $Lops) * 100)
            $c = [math]::Round($c)
            Write-Progress -Id 1 -activity "Building Cache Files" -Status "$c% Complete." -PercentComplete $c
            $Counter++

            $NewJobName = ($Job -replace 'ResourceJob_','')
            $TempJob = Receive-Job -Name $Job
            
            # v7.28: NULL-SAFE diagnostics - Check if $TempJob is null BEFORE calling methods
            if ($null -eq $TempJob) {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Job '$NewJobName' returned NULL")
            } else {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Job '$NewJobName' returned type: $($TempJob.GetType().Name)")
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Job '$NewJobName' has Keys property: $($null -ne $TempJob.Keys)")
                if ($TempJob.Keys) {
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Job '$NewJobName' key count: $($TempJob.Keys.Count)")
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Job '$NewJobName' keys: $($TempJob.Keys -join ', ')")
                }
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Job '$NewJobName' has .values property: $($null -ne $TempJob.values)")
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Job '$NewJobName' .values is empty: $([string]::IsNullOrEmpty($TempJob.values))")
            }
            
            # v7.15: CRITICAL FIX - Check if hashtable has data (not .values which doesn't exist)
            if ($TempJob -and $TempJob -is [System.Collections.Hashtable] -and $TempJob.Count -gt 0)
                {
                    $JobJSONName = ($NewJobName+'.json')
                    $JobFileName = Join-Path $DefaultPath 'ReportCache' $JobJSONName
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Creating Cache File: '+ $JobFileName)
                    $TempJob | ConvertTo-Json -Depth 40 | Out-File $JobFileName
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"✅ Cache file created for '$NewJobName'")
                }
            else
                {
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"❌ WARNING: Job '$NewJobName' returned no data - cache file NOT created")
                    if ($TempJob) {
                        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"   Reason: IsHashtable=$($TempJob -is [System.Collections.Hashtable]), Count=$($TempJob.Count)")
                    } else {
                        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"   Reason: TempJob is null")
                    }
                }
            
            Remove-Job -Name $Job -Force -ErrorAction SilentlyContinue
            Remove-Variable -Name TempJob

        }
    Clear-ARIMemory
    
    # v7.15: Report actual cache files created
    $CachePath = Join-Path $DefaultPath 'ReportCache'
    $ActualCacheFiles = (Get-ChildItem -Path $CachePath -Filter "*.json" -ErrorAction SilentlyContinue).Count
    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Cache Files Created: $ActualCacheFiles files in $CachePath")
    if ($ActualCacheFiles -eq 0) {
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'⚠️  WARNING: ZERO cache files were actually created!')
    }
}
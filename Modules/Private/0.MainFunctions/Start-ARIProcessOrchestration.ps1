<#
.Synopsis
Process orchestration for Azure Resource Inventory

.DESCRIPTION
This module orchestrates the processing of resources for Azure Resource Inventory.

.Link
https://github.com/microsoft/ARI/Modules/Private/0.MainFunctions/Start-ARIProcessOrchestration.ps1

.COMPONENT
This PowerShell Module is part of Azure Resource Inventory (ARI)

.NOTES
Version: 3.6.9
First Release Date: 15th Oct, 2024
Authors: Claudio Merola

#>

function Start-ARIProcessOrchestration {
    Param($Subscriptions, $Resources, $Retirements, $DefaultPath, $File, $Heavy, $InTag, $Automation)

        Write-Progress -activity 'Azure Inventory' -Status "21% Complete." -PercentComplete 21 -CurrentOperation "Starting to process extracted data.."

        <######################################################### IMPORT UNSUPPORTED VERSION LIST ######################################################################>

        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Importing List of Unsupported Versions.')

        $Unsupported = Get-ARIUnsupportedData

        <######################################################### RESOURCE GROUP JOB ######################################################################>

        if ($Automation.IsPresent)
            {
                Write-Output ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Processing Resources in Automation Mode')

                Start-ARIAutProcessJob -Resources $Resources -Retirements $Retirements -Subscriptions $Subscriptions -Heavy $Heavy -InTag $InTag -Unsupported $Unsupported
            }
        else
            {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Processing Resources in Regular Mode')

                Start-ARIProcessJob -Resources $Resources -Retirements $Retirements -Subscriptions $Subscriptions -DefaultPath $DefaultPath -InTag $InTag -Heavy $Heavy -Unsupported $Unsupported
            }

        Remove-Variable -Name Unsupported -ErrorAction SilentlyContinue

        <############################################################## RESOURCES PROCESSING #############################################################>

        if ($Automation.IsPresent)
            {
                Write-Output ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Waiting for Resource Jobs to Complete in Automation Mode')
                Get-Job | Where-Object {$_.name -like 'ResourceJob_*'} | Wait-Job
            }
        else
            {
                $JobNames = (Get-Job | Where-Object {$_.name -like 'ResourceJob_*'}).Name
                
                # v7.24 FIX: Proper null handling for Get-Job result
                # Get-Job returns null when no jobs found, must check null first before accessing .Count
                # Wrap in @() to ensure array type before checking Count
                if ($null -ne $JobNames -and @($JobNames).Count -gt 0) {
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Found $(@($JobNames).Count) remaining jobs to wait for")
                    
                    # v7.40.1: CRITICAL FIX - Fast capture instead of Wait-ARIJob
                    Write-Host "⚡ FAST CAPTURE: Polling for job completion..." -ForegroundColor Yellow
                    
                    $JobResults = @{}
                    $maxWaitSeconds = 30
                    $pollInterval = 0.5
                    $elapsedSeconds = 0
                    
                    while ($elapsedSeconds -lt $maxWaitSeconds) {
                        Start-Sleep -Milliseconds ($pollInterval * 1000)
                        $elapsedSeconds += $pollInterval
                        
                        $allJobs = Get-Job -Name $JobNames -ErrorAction SilentlyContinue
                        
                        if ($allJobs) {
                            foreach ($job in $allJobs) {
                                if ($job.State -eq 'Completed' -and -not $JobResults.ContainsKey($job.Name)) {
                                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Capturing $($job.Name)")
                                    $output = Receive-Job -Job $job -Keep -ErrorAction SilentlyContinue
                                    $JobResults[$job.Name] = @{
                                        Name = $job.Name
                                        Output = $output
                                        State = $job.State
                                    }
                                }
                            }
                            
                            $remainingJobs = $allJobs | Where-Object { $_.State -in @('Running', 'NotStarted') }
                            if ($remainingJobs.Count -eq 0 -and $JobResults.Count -eq $JobNames.Count) {
                                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"All $($JobResults.Count) jobs captured")
                                break
                            }
                        }
                    }
                    
                    # Clean up any remaining jobs after Wait-ARIJob
                    # v7.40: CRITICAL CHANGE - Pass captured job results to Build-ARICacheFiles
                    Build-ARICacheFiles -DefaultPath $DefaultPath -JobResults $JobResults
                }
                else {
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'No remaining jobs found - Start-ARIProcessJob handled all batches internally')
                }
            }

        if ($Automation.IsPresent)
            {
                Write-Output ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Processing Resources in Automation Mode')
            }
        else
            {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Finished Waiting for Resource Jobs.')
            }

        Write-Progress -activity 'Azure Inventory' -Status "60% Complete." -PercentComplete 60 -CurrentOperation "Completed Data Processing Phase.."

}
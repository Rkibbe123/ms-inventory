<#
.Synopsis
Module for Excel Job Processing

.DESCRIPTION
This script processes inventory modules and builds the Excel report.

.Link
https://github.com/microsoft/ARI/Modules/Private/3.ReportingFunctions/Start-ARIExcelJob.ps1

.COMPONENT
This PowerShell Module is part of Azure Resource Inventory (ARI)

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola
#>

function Start-ARIExcelJob {
    Param($ReportCache, $File, $TableStyle)

    $ParentPath = (get-item $PSScriptRoot).parent.parent
    $InventoryModulesPath = Join-Path $ParentPath 'Public' 'InventoryModules'
    $ModuleFolders = Get-ChildItem -Path $InventoryModulesPath -Directory

    Write-Progress -activity 'Azure Inventory' -Status "68% Complete." -PercentComplete 68 -CurrentOperation "Starting the Report Loop.."

    $ModulesCount = [string](Get-ChildItem -Path $InventoryModulesPath -Recurse -Filter "*.ps1").count

    Write-Output 'Starting to Build Excel Report.'
    Write-Host 'Supported Resource Types: ' -NoNewline -ForegroundColor Green
    Write-Host $ModulesCount -ForegroundColor Cyan

    # Create initial Excel file to ensure it exists before modules try to append
    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Creating initial Excel file: $File")
    try {
        # Create a minimal initial worksheet so the file exists
        @([PSCustomObject]@{Info='Azure Resource Inventory Report'}) | 
            Export-Excel -Path $File -WorksheetName 'Info' -AutoSize -TableStyle $TableStyle
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Initial Excel file created successfully.')
    }
    catch {
        Write-Error "Failed to create initial Excel file: $_"
        throw
    }

    $Lops = $ModulesCount
    $ReportCounter = 0

    Foreach ($ModuleFolder in $ModuleFolders)
        {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Processing module folder: $($ModuleFolder.Name)")
            $CacheData = $null
            $ModulePath = Join-Path $ModuleFolder.FullName '*.ps1'
            $ModuleFiles = Get-ChildItem -Path $ModulePath
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Found $($ModuleFiles.Count) module files in $($ModuleFolder.Name)")

            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"ReportCache path: $ReportCache")
            $CacheFiles = Get-ChildItem -Path $ReportCache -Recurse
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Total cache files found: $($CacheFiles.Count)")
            if ($CacheFiles.Count -gt 0) {
                $CacheFileNames = ($CacheFiles | Select-Object -ExpandProperty Name) -join ', '
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Cache file names: $CacheFileNames")
            }
            $JSONFileName = ($ModuleFolder.Name + '.json')
            $CacheFile = $CacheFiles | Where-Object { $_.Name -like "*$JSONFileName" }
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Looking for cache file: $JSONFileName, Found: $($CacheFile.Count) matches")

            if ($CacheFile)
                {
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Reading cache file: $($CacheFile.FullName)")
                    $CacheFileContent = New-Object System.IO.StreamReader($CacheFile.FullName)
                    $CacheData = $CacheFileContent.ReadToEnd()
                    $CacheFileContent.Dispose()
                    $CacheData = $CacheData | ConvertFrom-Json
                    $CacheDataProperties = ($CacheData | Get-Member -MemberType NoteProperty).Count
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Cache data loaded with $CacheDataProperties properties")
                }
            else
                {
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"WARNING: No cache file found for module folder: $($ModuleFolder.Name)")
                }

            Foreach ($Module in $ModuleFiles)
                {
                    $c = (($ReportCounter / $Lops) * 100)
                    $c = [math]::Round($c)
                    Write-Progress -Id 1 -activity "Building Report" -Status "$c% Complete." -PercentComplete $c

                    $ModuleFileContent = New-Object System.IO.StreamReader($Module.FullName)
                    $ModuleData = $ModuleFileContent.ReadToEnd()
                    $ModuleFileContent.Dispose()
                    $ModName = $Module.Name.replace(".ps1","")

                    $SmaResources = $CacheData.$ModName

                    $ModuleResourceCount = $SmaResources.count
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Module '$ModName': Resource count = $ModuleResourceCount")

                    if ($ModuleResourceCount -gt 0)
                    {
                        Start-Sleep -Milliseconds 25
                        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Running Module: '$ModName'. Excel Rows: $ModuleResourceCount")

                        $ScriptBlock = [Scriptblock]::Create($ModuleData)

                        Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $PSScriptRoot, $null, $InTag, $null, $null, 'Reporting', $file, $SmaResources, $TableStyle, $null

                    }

                    $ReportCounter ++

                }
                Remove-Variable -Name CacheData
                Remove-Variable -Name SmaResources
                Clear-ARIMemory
        }
        Write-Progress -Id 1 -activity "Building Report" -Status "100% Complete." -Completed
    }
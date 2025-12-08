# Tail Container Logs - Similar to "tail -f" for Azure Container Apps
# Shows the last N lines and can follow new output

[CmdletBinding()]
param(
    [string]$Name = $(if ($env:CONTAINER_APP_NAME) { $env:CONTAINER_APP_NAME } else { "ms-inventory" }),
    [string]$ResourceGroup = $(if ($env:CONTAINER_APP_RG) { $env:CONTAINER_APP_RG } else { "rg-rkibbe-2470" }),
    [int]$Tail = 100,
    [switch]$Follow
)

$CONTAINER_APP = $Name
$RESOURCE_GROUP = $ResourceGroup

Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║        Container Logs - Live Stream                        ║" -ForegroundColor Cyan
Write-Host "║        Press Ctrl+C to stop                                ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Starting log stream from container..." -ForegroundColor Yellow
Write-Host ""

# Build argument list
$argsList = @(
    'containerapp', 'logs', 'show',
    '--name', $CONTAINER_APP,
    '--resource-group', $RESOURCE_GROUP,
    '--tail', $Tail,
    '--type', 'console'
)
if ($Follow) { $argsList += '--follow' }

az @argsList

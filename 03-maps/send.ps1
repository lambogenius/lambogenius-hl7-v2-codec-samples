<#
.SYNOPSIS
    Sends an ER7 message to the patient-summary workflow and prints the summary and the xpath() headers.

.EXAMPLE
    ./send.ps1 patient-summary messages/adt-a01.hl7
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('patient-summary')]
    [string]$Workflow,

    [Parameter(Mandatory, Position = 1)]
    [string]$File,

    [string]$BaseUrl = 'http://localhost:7203'
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/Hl7Sample.psm1') -Force
$response = Invoke-Hl7Workflow $Workflow $File -BaseUrl $BaseUrl
foreach ($header in 'x-map', 'x-patient-class', 'x-observation-count') { Write-Host "$header`: $($response.Headers[$header])" }
Write-Hl7Response $Workflow $File $response

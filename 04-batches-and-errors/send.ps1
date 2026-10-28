<#
.SYNOPSIS
    Sends an ER7 file to one of the sample's workflows and prints the answer.

.EXAMPLE
    ./send.ps1 receive messages/batch.hl7
.EXAMPLE
    ./send.ps1 receive messages/batch.hl7 -Query schemaless=true
.EXAMPLE
    ./send.ps1 inspect messages/missing-pv1.hl7
.EXAMPLE
    ./send.ps1 enhanced-ack messages/enhanced.hl7
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('receive', 'inspect', 'enhanced-ack')]
    [string]$Workflow,

    [Parameter(Mandatory, Position = 1)]
    [string]$File,

    [string]$Query = '',

    [string]$BaseUrl = 'http://localhost:7204'
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/Hl7Sample.psm1') -Force
$response = Invoke-Hl7Workflow $Workflow $File -BaseUrl $BaseUrl -Query $Query
if ($Workflow -eq 'receive') { foreach ($header in 'x-message-count', 'x-ack-codes') { Write-Host "$header`: $($response.Headers[$header])" } }
Write-Hl7Response $Workflow $File $response

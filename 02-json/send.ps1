<#
.SYNOPSIS
    Sends a file to one of the sample's workflows and prints the answer.

.EXAMPLE
    ./send.ps1 to-json messages/adt-a01.hl7
.EXAMPLE
    ./send.ps1 from-json messages/adt-a01.json -Query validate=true
.EXAMPLE
    ./send.ps1 transfer-patient messages/adt-a01.hl7 -Query "ward=WARD7&room=702&bed=A"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('to-json', 'from-json', 'transfer-patient')]
    [string]$Workflow,

    [Parameter(Mandatory, Position = 1)]
    [string]$File,

    [string]$Query = '',

    [string]$BaseUrl = 'http://localhost:7202'
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/Hl7Sample.psm1') -Force
Write-Hl7Response $Workflow $File (Invoke-Hl7Workflow $Workflow $File -BaseUrl $BaseUrl -Query $Query)

<#
.SYNOPSIS
    Sends a file to one of the sample's workflows and prints the answer.

.EXAMPLE
    ./send.ps1 decode messages/adt-a01.hl7
.EXAMPLE
    ./send.ps1 encode messages/adt-a08.xml -Query validate=true
.EXAMPLE
    ./send.ps1 create-ack messages/adt-a01.hl7 -AckCode AE -ErrorMessage 'Unknown attending doctor'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('decode', 'decode-schemaless', 'encode', 'create-ack', 'round-trip')]
    [string]$Workflow,

    [Parameter(Mandatory, Position = 1)]
    [string]$File,

    [string]$Query = '',

    # create-ack only: the ACK code and the error text.
    [string]$AckCode = 'AA',
    [string]$ErrorMessage = '',

    [string]$BaseUrl = 'http://localhost:7201'
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/Hl7Sample.psm1') -Force
$response = if ($Workflow -eq 'create-ack') {
    $body = @{ message = (Get-Content $File -Raw); ackCode = $AckCode; errorMessage = $ErrorMessage } | ConvertTo-Json
    Invoke-Hl7Workflow $Workflow -Body $body -ContentType 'application/json' -BaseUrl $BaseUrl -Query $Query
}
else {
    Invoke-Hl7Workflow $Workflow $File -BaseUrl $BaseUrl -Query $Query
}
Write-Hl7Response $Workflow $File $response

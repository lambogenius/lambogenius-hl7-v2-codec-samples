<#
.SYNOPSIS
    Builds and runs the batches and errors sample on http://localhost:7204, with Azurite.

.DESCRIPTION
    Needs the .NET 8 SDK, Azure Functions Core Tools 4, Azurite, PowerShell 7.2 and the HL7 v2 Codec package in
    ../packages. With -V2XmlFolder (or the HL7_V2XML_FOLDER environment variable), a folder of HL7's v2.5 v2.xml
    schemas, it first generates the ADT_A01 schema into Artifacts/Schemas. Without it, the schemaless steps still run.
    Ctrl+C stops the Logic App and what this script started. Then, in another window: ./demo.ps1, or ./send.ps1.
#>
[CmdletBinding()]
param(
    [string]$V2XmlFolder = $env:HL7_V2XML_FOLDER,
    [int]$Port = 7204,
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug'
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/Hl7Sample.psm1') -Force
Start-Hl7Sample -App $PSScriptRoot -Port $Port -Configuration $Configuration -Schemas ADT_A01 -V2XmlFolder $V2XmlFolder -Examples @(
    './send.ps1 receive messages/batch.hl7'
    './send.ps1 receive messages/unknown-structure.hl7'
    './send.ps1 enhanced-ack messages/enhanced.hl7'
)

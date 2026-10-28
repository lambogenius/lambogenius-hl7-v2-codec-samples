#Requires -Version 7.2
<#
.SYNOPSIS
    Generates codec message schemas from HL7's v2.xml schemas, with no build step.

.DESCRIPTION
    Same converter and output as Hl7SchemaGen.exe: this script compiles V2XmlSchemaConverter.cs (next to it) in memory
    with Add-Type, so only PowerShell 7.2 or later is needed.

    Reads HL7's v2.xml schemas (download them from hl7.org with your own HL7 account) and writes one XSD per message
    structure to <Out>/<version>/<ROOT>.xsd: MSH and the body in one schema, named as the codec expects
    (PID_5_PatientName, XPN_0_FamilyName, ADT_A01_PROCEDURE). Without -Message every structure is written.
    -Out can be a Logic App's Artifacts/Schemas folder.

.EXAMPLE
    ./Hl7SchemaGen.ps1 -Source C:\hl7\v2xml\2.5.1 -Out C:\MyLogicApp\Artifacts\Schemas

.EXAMPLE
    ./Hl7SchemaGen.ps1 -Source C:\hl7\v2xml\2.5.1 -Out .\schemas -Message ADT_A01, ORU_R01 -PlainRoot

.EXAMPLE
    ./Hl7SchemaGen.ps1 -Source C:\hl7\v2xml\2.5.1 -List
#>
[CmdletBinding(DefaultParameterSetName = 'Generate')]
param(
    # Folder with the v2.xml schemas (segments.xsd and the message files), or a folder above it.
    [Parameter(Mandatory, Position = 0)]
    [string] $Source,

    # Output folder; the schemas go to <Out>/<version>/.
    [Parameter(Mandatory, ParameterSetName = 'Generate')]
    [string] $Out,

    # Message structures to write (e.g. ADT_A01); all when left out.
    [Parameter(ParameterSetName = 'Generate')]
    [string[]] $Message,

    # HL7 version (e.g. 2.5.1) when the files don't name it.
    [string] $Version,

    # Target namespace of the message roots.
    [Parameter(ParameterSetName = 'Generate')]
    [string] $Namespace,

    # Root named ADT_A01 instead of ADT_A01_251.
    [Parameter(ParameterSetName = 'Generate')]
    [switch] $PlainRoot,

    # Only list the message structures.
    [Parameter(Mandatory, ParameterSetName = 'List')]
    [switch] $List
)

$ErrorActionPreference = 'Stop'

if (-not ('Lambogenius.Hl7SchemaGen.V2XmlSchemaConverter' -as [type])) {
    $code = Join-Path $PSScriptRoot 'V2XmlSchemaConverter.cs'
    if (-not (Test-Path $code)) { throw "V2XmlSchemaConverter.cs must be next to this script ($PSScriptRoot)." }
    Add-Type -Path $code -ReferencedAssemblies System.Runtime, System.Memory, System.Collections,
        System.Collections.NonGeneric, System.Linq, System.Text.RegularExpressions, System.Text.Encoding.Extensions,
        System.Xml.ReaderWriter, System.Xml.XDocument
}

# PowerShell turns $null into "" for string arguments; NullString keeps "not given" for the converter.
$versionArg = if ($Version) { $Version } else { [NullString]::Value }
try {
    $converter = [Lambogenius.Hl7SchemaGen.V2XmlSchemaConverter]::Load($Source, $versionArg)
}
catch {
    Write-Error ($_.Exception.InnerException ?? $_.Exception).Message -ErrorAction Continue
    exit 1
}

Write-Host "HL7 v$($converter.Version) v2.xml schemas in $($converter.Folder): $($converter.MessageNames.Count) message structures."
if ($List) {
    $converter.MessageNames
    exit 0
}

$options = [Lambogenius.Hl7SchemaGen.V2XmlGenerateOptions]::new()
$options.VersionedRoot = -not $PlainRoot
if ($Namespace) { $options.Namespace = $Namespace }

$messages = if ($Message) { $Message } else { $converter.MessageNames }
$unknown = @($messages | Where-Object { -not $converter.MessageNames.Contains($_) })
if ($unknown) {
    Write-Error "Not in these schemas: $($unknown -join ', '). Use -List to see the structures." -ErrorAction Continue
    exit 1
}

$outFolder = [IO.Path]::GetFullPath($Out, (Get-Location).ProviderPath)
foreach ($m in $messages) {
    $path = $converter.Write($m, $outFolder, $options)
    $dropped = if ($converter.DroppedWildcards -gt 0) { " ($($converter.DroppedWildcards) xsd:any left out)" } else { '' }
    Write-Host "  $m -> $path$dropped"
}
Write-Host "$(@($messages).Count) schema(s) written."

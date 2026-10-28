<#
    Shared helpers for the samples' run.ps1, demo.ps1 and send.ps1 scripts.

    Start-Hl7Sample generates the sample's schemas (when given HL7's v2.xml schemas), builds the sample Logic App and
    runs it with Azurite. Invoke-Hl7Workflow calls a workflow's HTTP trigger. Initialize-Demo, Step, Check, Skip and
    Complete-Demo print a demo's checks and set its exit code.
#>

$ErrorActionPreference = 'Stop'
$script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
$script:Generator = Join-Path $PSScriptRoot '../schemagen/Hl7SchemaGen.ps1'
$script:Failures = 0
$script:Passes = 0
$script:Skipped = 0

# The test messages say MSH-12 = 2.5, and the codec picks the schema whose root carries that version (ADT_A01_25).
$script:HL7Version = '2.5'

function Find-Tool([string]$name, [string]$hint) {
    # npm installs PowerShell and cmd shims; Start-Process needs the .exe or .cmd.
    $tool = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Where-Object Extension -in '.exe', '.cmd', '' |
        Sort-Object { $_.Extension -ne '.exe' } | Select-Object -First 1
    if (-not $tool) { throw "$name was not found on PATH. $hint" }
    $tool.Source
}

function Test-Listening([int]$port) {
    $client = [System.Net.Sockets.TcpClient]::new()
    try { $client.ConnectAsync('127.0.0.1', $port).Wait(300) -and $client.Connected } catch { $false } finally { $client.Dispose() }
}

function Wait-Until([scriptblock]$condition, [string]$what, [int]$seconds = 120) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while (-not (& $condition)) {
        if ((Get-Date) -gt $deadline) { throw "Timed out waiting for $what." }
        Start-Sleep -Milliseconds 500
    }
}

function Get-Hl7CodecVersion([string]$app) {
    [xml]$project = Get-Content (Join-Path $app 'LogicApp.csproj')
    $version = $project.Project.PropertyGroup | ForEach-Object { $_.Hl7CodecVersion } | Where-Object { $_ } | Select-Object -First 1
    if ($version -is [System.Xml.XmlElement]) { $version = $version.'#text' }
    if ($version) { $version } else { '1.1.0' }
}

<#
.SYNOPSIS
    The folder that holds a sample's generated schemas, and whether the given roots (ADT_A01_25, ...) are in it.
#>
function Get-Hl7SchemaFolder([string]$App) { Join-Path $App "Artifacts/Schemas/$script:HL7Version" }

function Test-Hl7Schemas([string]$App, [string[]]$Roots) {
    $folder = Get-Hl7SchemaFolder $App
    @($Roots | Where-Object { -not (Test-Path (Join-Path $folder "$_.xsd")) }).Count -eq 0
}

<#
.SYNOPSIS
    Writes the message schemas a sample needs into <App>/Artifacts/Schemas, from a folder of HL7's v2.xml schemas, with
    the HL7 v2 Schema Generator in shared/schemagen. The output is HL7's content: git ignores it.
#>
function New-Hl7Schemas {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$App,
        [Parameter(Mandatory)][string]$V2XmlFolder,
        [Parameter(Mandatory)][string[]]$Messages
    )
    if (-not (Test-Path $V2XmlFolder -PathType Container)) { throw "-V2XmlFolder: $V2XmlFolder is not a folder." }
    $V2XmlFolder = (Resolve-Path $V2XmlFolder).Path
    $pwsh = (Get-Process -Id $PID).Path
    $out = Join-Path $App 'Artifacts/Schemas'

    # Read the version first, so a wrong download doesn't replace good schemas.
    $listing = & $pwsh -NoProfile -File $script:Generator -Source $V2XmlFolder -List 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE) { throw "The schema generator could not read $V2XmlFolder`n$($listing -join "`n")" }
    $version = [regex]::Match(($listing -join "`n"), 'HL7 v(\S+) v2\.xml').Groups[1].Value
    if ($version -ne $script:HL7Version) {
        throw "$V2XmlFolder holds HL7 v$version v2.xml schemas. The samples' messages are HL7 v$script:HL7Version (MSH-12), so point -V2XmlFolder at the v$script:HL7Version schemas (the folder with segments.xsd and ADT_A01.xsd)."
    }

    if (Test-Path $out) { Remove-Item $out -Recurse -Force }
    Write-Host "Generating $($Messages -join ', ') from the HL7 v$version v2.xml schemas in $V2XmlFolder ..."
    $output = & $pwsh -NoProfile -File $script:Generator -Source $V2XmlFolder -Out $out -Message $Messages 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE) { throw "The schema generator failed:`n$($output -join "`n")" }
    $output | Where-Object { $_ -match ' -> ' } | ForEach-Object { Write-Host ($_ -replace [regex]::Escape($App), '.') }
}

<#
.SYNOPSIS
    Generates the schemas (with -V2XmlFolder), builds one sample Logic App and runs it with `func start` in the current
    window. Ctrl+C stops it and whatever this function started; an Azurite that was already running is left alone.
#>
function Start-Hl7Sample {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$App,
        [Parameter(Mandatory)][int]$Port,
        [string[]]$Schemas = @(),
        [string]$V2XmlFolder,
        [string[]]$Examples = @(),
        [ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug'
    )

    $logs = Join-Path $App 'logs'
    $started = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()

    # 1. Prerequisites.
    if ($PSVersionTable.PSVersion -lt [version]'7.2') { throw 'PowerShell 7.2 or later is required: https://aka.ms/powershell' }
    if (-not ((dotnet --list-sdks) -match '^8\.')) { throw '.NET SDK 8 is required: https://dotnet.microsoft.com/download/dotnet/8.0' }
    $func = Find-Tool 'func' 'Install Azure Functions Core Tools 4: npm install -g azure-functions-core-tools@4'
    Write-Host "dotnet $((dotnet --version)), func $((& $func --version)), PowerShell $($PSVersionTable.PSVersion)"
    New-Item -ItemType Directory -Force $logs | Out-Null

    # 2. The HL7 v2 Codec package, downloaded from lambogenius.com into packages/.
    $version = Get-Hl7CodecVersion $App
    $package = Join-Path $script:RepoRoot "packages/Lambogenius.Hl7Codec.LogicApps.$version.nupkg"
    if (-not (Test-Path $package)) {
        throw "packages/Lambogenius.Hl7Codec.LogicApps.$version.nupkg is missing. Sign in at https://lambogenius.com/app/downloads/hl7-v2-codec, download it, and save it in $(Join-Path $script:RepoRoot 'packages')."
    }

    # 3. Schemas, generated from HL7's v2.xml schemas. Without them the sample runs its schemaless steps only.
    if ($Schemas) {
        $roots = $Schemas | ForEach-Object { "$($_)_$($script:HL7Version.Replace('.', ''))" }
        if ($V2XmlFolder) {
            New-Hl7Schemas -App $App -V2XmlFolder $V2XmlFolder -Messages $Schemas
        }
        elseif (Test-Hl7Schemas $App $roots) {
            Write-Host "Schemas: using $($roots -join ', ') in Artifacts/Schemas, generated earlier. Delete that folder to run without them."
        }
        else {
            Write-Host "Schemas: none, so demo.ps1 runs the steps that need no schema and skips the others. To add them, download HL7's v2.5 v2.xml schemas (free, with your hl7.org account) and run ./run.ps1 -V2XmlFolder <folder>." -ForegroundColor Yellow
        }
    }

    try {
        # 4. Storage emulator.
        $storagePorts = 10000, 10001, 10002
        $busy = @($storagePorts | Where-Object { Test-Listening $_ })
        if ($busy.Count -eq $storagePorts.Count) {
            Write-Host 'Storage emulator: using the one already listening on ports 10000-10002.'
        }
        else {
            if ($busy) {
                # Another program holds some of the default ports (VS Code sometimes holds 10001), so Azurite gets free
                # ones and the Logic App is pointed at them. Core Tools prefers this environment variable over
                # local.settings.json. The key is the emulator's public, well-known development account key.
                $first = 10100
                while (@($first..($first + 2) | Where-Object { Test-Listening $_ }).Count) { $first += 3 }
                $storagePorts = $first, ($first + 1), ($first + 2)
                Write-Host "Another program is using port(s) $($busy -join ', '); Azurite will listen on $($storagePorts -join ', ')."
                $env:AzureWebJobsStorage = 'DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;' +
                    'AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;' +
                    "BlobEndpoint=http://127.0.0.1:$($storagePorts[0])/devstoreaccount1;" +
                    "QueueEndpoint=http://127.0.0.1:$($storagePorts[1])/devstoreaccount1;" +
                    "TableEndpoint=http://127.0.0.1:$($storagePorts[2])/devstoreaccount1;"
            }
            $azurite = Find-Tool 'azurite' 'Install Azurite: npm install -g azurite'
            $data = Join-Path $App '.azurite'
            New-Item -ItemType Directory -Force $data | Out-Null
            Write-Host "Starting Azurite (data in $data) ..."
            $started.Add((Start-Process $azurite -ArgumentList '--silent', '--skipApiVersionCheck', '--location', "`"$data`"",
                '--blobPort', $storagePorts[0], '--queuePort', $storagePorts[1], '--tablePort', $storagePorts[2] -PassThru -WindowStyle Hidden))
            Wait-Until { @($storagePorts | Where-Object { Test-Listening $_ }).Count -eq 3 } "Azurite on ports $($storagePorts -join ', ')" 60
        }

        # 5. Build and run the Logic App.
        if (-not (Test-Path (Join-Path $App 'local.settings.json'))) { Copy-Item (Join-Path $App 'local.settings.sample.json') (Join-Path $App 'local.settings.json') }
        if (Test-Listening $Port) { throw "Port $Port is already in use. Pass -Port <other port>." }
        $output = Join-Path $App "bin/$Configuration/net8.0"
        # The build copies Artifacts/ but never deletes from the output, so drop old schemas there first: the Logic App
        # then has exactly the schemas in Artifacts/Schemas.
        if (Test-Path (Join-Path $output 'Artifacts/Schemas')) { Remove-Item (Join-Path $output 'Artifacts/Schemas') -Recurse -Force }
        Write-Host 'Building the Logic App ...'
        dotnet build (Join-Path $App 'LogicApp.csproj') -c $Configuration --nologo -v q -clp:ErrorsOnly
        if ($LASTEXITCODE) { throw 'The Logic App failed to build.' }

        Write-Host ''
        Write-Host "Starting the Logic App on http://localhost:$Port. In another window, try:" -ForegroundColor Green
        foreach ($example in $Examples) { Write-Host "  $example" -ForegroundColor Green }
        Write-Host '  ./demo.ps1        # every step, checked' -ForegroundColor Green
        Write-Host 'Press Ctrl+C to stop.' -ForegroundColor Green
        Write-Host ''
        Push-Location $output
        try { & $func start --port $Port } finally { Pop-Location }
    }
    finally {
        foreach ($process in $started) {
            if (-not $process.HasExited) {
                Write-Host "Stopping $($process.ProcessName) (pid $($process.Id))"
                taskkill /PID $process.Id /T /F | Out-Null
            }
        }
    }
}

<#
.SYNOPSIS
    Posts a file (or -Body text) to a workflow's HTTP trigger ("When_an_HTTP_request_is_received") and returns the
    status, the parsed body (JSON) or the text, the content type and the time taken. .hl7 files go as text/plain.
#>
function Invoke-Hl7Workflow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Workflow,
        [Parameter(Position = 1)][string]$File,
        [string]$Body,
        [string]$ContentType,
        [Parameter(Mandatory)][string]$BaseUrl,
        [string]$Query = '',
        [hashtable]$Headers = @{}
    )

    if ($File) {
        $path = (Resolve-Path $File).Path
        $bytes = [System.IO.File]::ReadAllBytes($path)
        if (-not $ContentType) {
            $ContentType = switch -Wildcard ($path) { '*.xml' { 'application/xml' } '*.json' { 'application/json' } default { 'text/plain' } }
        }
    }
    else {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
        if (-not $ContentType) { $ContentType = 'text/plain' }
    }
    # Request triggers need a signed URL; the local runtime hands it out through its management API.
    try {
        $url = (Invoke-RestMethod -Method Post -Uri "$BaseUrl/runtime/webhooks/workflow/api/management/workflows/$Workflow/triggers/When_an_HTTP_request_is_received/listCallbackUrl?api-version=2020-05-01-preview").value
    }
    catch {
        throw "Could not reach the Logic App at $BaseUrl, or it has no workflow '$Workflow'. Is ./run.ps1 running? $($_.Exception.Message)"
    }
    if ($Query) { $url += "&$Query" }

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-WebRequest -Method Post -Uri $url -Body $bytes -ContentType $ContentType -Headers $Headers -SkipHttpErrorCheck
    $type = "$($response.Headers['Content-Type'])"
    $text = if ($response.Content -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($response.Content) } else { $response.Content }
    [pscustomobject]@{
        Status      = [int]$response.StatusCode
        ContentType = $type
        Headers     = $response.Headers
        Text        = $text
        Body        = if ($type -like '*json*' -and $text) { $text | ConvertFrom-Json } else { $text }
        Seconds     = $watch.Elapsed.TotalSeconds
    }
}

<#
.SYNOPSIS
    Prints a workflow response (used by the samples' send.ps1). HL7 segments, which end with CR, go on their own lines.
#>
function Write-Hl7Response([string]$workflow, [string]$file, $response) {
    $color = if ($response.Status -lt 300) { 'Green' } else { 'Red' }
    Write-Host "POST $workflow $(Split-Path $file -Leaf) -> HTTP $($response.Status)" -ForegroundColor $color
    if ($response.ContentType -like '*json*' -and $response.Text) { $response.Body | ConvertTo-Json -Depth 30 }
    else { ($response.Text -replace "`r`n?", "`n").TrimEnd() }
}

<#
.SYNOPSIS
    The segments of an ER7 message (split on CR, LF or CRLF), as an array.
#>
function Get-Segments([string]$er7) { , @($er7 -split "[`r`n]+" | Where-Object { $_ }) }

<#
.SYNOPSIS
    Starts a demo: checks that the Logic App answers, and says whether the schemas the steps need are there.
    Returns $true when they are.
#>
function Initialize-Demo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$App,
        [Parameter(Mandatory)][string]$BaseUrl,
        [string[]]$Schemas = @()
    )
    try { Invoke-WebRequest -Uri "$BaseUrl/runtime/webhooks/workflow/api/management/workflows?api-version=2020-05-01-preview" -TimeoutSec 10 | Out-Null }
    catch { Write-Host "The Logic App does not answer on $BaseUrl. Start it with ./run.ps1 and wait for 'Host lock lease acquired'." -ForegroundColor Red; exit 1 }

    $roots = $Schemas | ForEach-Object { "$($_)_$($script:HL7Version.Replace('.', ''))" }
    $has = $Schemas.Count -gt 0 -and (Test-Hl7Schemas $App $roots)
    if ($has) { Write-Host "Schemas: $($roots -join ', ') in Artifacts/Schemas/$script:HL7Version (generated from HL7's v2.xml)." }
    elseif ($Schemas) {
        Write-Host "Schemas: none. Steps that need $($roots -join ', ') are skipped. To run them: ./run.ps1 -V2XmlFolder <HL7 v2.5 v2.xml folder>." -ForegroundColor Yellow
    }
    $has
}

function Step([string]$title) { Write-Host ''; Write-Host $title -ForegroundColor Cyan }

function Check([string]$what, [bool]$ok, [string]$actual = '') {
    if ($ok) { Write-Host "  ok    $what" -ForegroundColor Green; $script:Passes++ }
    else { Write-Host "  FAIL  $what $actual" -ForegroundColor Red; $script:Failures++ }
}

function Skip([string]$what, [string]$why = 'needs the schemas: ./run.ps1 -V2XmlFolder <folder>') {
    Write-Host "  skip  $what ($why)" -ForegroundColor Yellow
    $script:Skipped++
}

function Show([string]$text) { Write-Host (($text -replace "`r`n?", "`n").TrimEnd() -replace '(?m)^', '        ') -ForegroundColor DarkGray }

function Complete-Demo {
    Write-Host ''
    $summary = "$script:Passes passed, $script:Failures failed, $script:Skipped skipped."
    if ($script:Failures) { Write-Host $summary -ForegroundColor Red; Write-Host "$script:Failures check(s) failed." -ForegroundColor Red; exit 1 }
    Write-Host $summary
    if ($script:Skipped) { Write-Host "$script:Skipped step(s) skipped: they need the schemas. Run ./run.ps1 -V2XmlFolder <folder> to include them." -ForegroundColor Yellow }
    Write-Host 'All checks passed.' -ForegroundColor Green
    exit 0
}

Export-ModuleMember -Function Start-Hl7Sample, New-Hl7Schemas, Test-Hl7Schemas, Get-Hl7SchemaFolder, Invoke-Hl7Workflow, Write-Hl7Response,
    Get-Segments, Initialize-Demo, Step, Check, Skip, Show, Complete-Demo, Test-Listening

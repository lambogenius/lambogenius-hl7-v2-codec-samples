<#
.SYNOPSIS
    Sends a batch, invalid messages, an unknown message type, an unsupported version, a Z segment and enhanced-mode
    messages, and checks every ACK. Start the sample first with ./run.ps1. Steps that need the ADT_A01 schema are
    skipped (not failed) when it hasn't been generated; their schemaless counterparts run instead.
    Exits with 1 when a check fails.
#>
[CmdletBinding()]
param([string]$BaseUrl = 'http://localhost:7204')

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/Hl7Sample.psm1') -Force
Set-Location $PSScriptRoot
$schemas = Initialize-Demo -App $PSScriptRoot -BaseUrl $BaseUrl -Schemas ADT_A01

function Send([string]$workflow, [string]$file, [string]$query = '') {
    $r = Invoke-Hl7Workflow $workflow $file -BaseUrl $BaseUrl -Query $query
    Write-Host "  POST $workflow $(Split-Path $file -Leaf)$(if ($query) { " ?$query" }) -> HTTP $($r.Status)"
    $r
}
function Msa($segments) { @($segments | Where-Object { $_ -like 'MSA|*' }) }

Step '1. An FHS/BHS batch of three ADT^A01s, answered with one batch ACK.'
if ($schemas) {
    $r = Send 'receive' 'messages/batch.hl7'
    $s = Get-Segments $r.Text
    Check 'HTTP 200, three messages, ACK codes AA, CA, AE' ($r.Status -eq 200 -and "$($r.Headers['x-message-count'])" -eq '3' -and "$($r.Headers['x-ack-codes'])" -eq 'AA,CA,AE') "($($r.Status) $($r.Headers['x-message-count']) $($r.Headers['x-ack-codes']))"
    Check 'the batch ACK is wrapped in FHS/BHS ... BTS|3/FTS|1, back to the sender' ($s[0] -like 'FHS|^~\&|LAMBO-EMR|LAMBO CLINIC|NWD-ADT|NORTHWIND GENERAL|*|NWD-F-0001' -and $s[1] -like 'BHS|*|NWD-B-0001' -and $s[-2] -eq 'BTS|3' -and $s[-1] -eq 'FTS|1') (($s[0], $s[1], $s[-2], $s[-1]) -join ' / ')
    $msa = Msa $s
    Check 'NWD000501 accepted (AA); NWD000502 asks for enhanced mode (MSH-15 AL), so a commit ACK (CA)' ($msa[0] -eq 'MSA|AA|NWD000501' -and $msa[1] -eq 'MSA|CA|NWD000502') ($msa -join ' / ')
    Check 'NWD000503 has no PV1: AE, and an ERR segment with code 100 (segment sequence error)' ($msa[2] -eq 'MSA|AE|NWD000503|Required segment PV1 is missing.' -and ($s -contains 'ERR||PID^3|100^Segment sequence error^HL70357|E||||Required segment PV1 is missing.')) ($s -join ' / ')
    Show ($s -join "`n")
}
else {
    Skip 'the batch checked against ADT_A01_25 (AA, CA, AE)'
}
$r = Send 'receive' 'messages/batch.hl7' 'schemaless=true'
$s = Get-Segments $r.Text
$expected = if ($schemas) { 'AA,CA,AE' } else { 'AA,CA,AA' }
Check "with &schemaless=true: $expected$(if (-not $schemas) { ' (with no schema, nothing says PV1 is required)' })" ("$($r.Headers['x-ack-codes'])" -eq $expected -and $s[0] -like 'FHS|*' -and $s[-1] -eq 'FTS|1') "($($r.Headers['x-ack-codes']))"

Step '2. Validation errors: the ACK is AE, with an ERR segment per error.'
if ($schemas) {
    $r = Send 'inspect' 'messages/missing-pv1.hl7'
    $d = $r.Body
    Check 'success false, AE, the error has a code from table 0357, a severity and a location' (
        $d.success -eq $false -and $d.ackCode -eq 'AE' -and $d.errors[0].code -eq '100' -and $d.errors[0].severity -eq 'Error' -and $d.errors[0].location -like 'OBX*') "($($d.ackCode) $($d.errors | ConvertTo-Json -Compress))"
    Check 'the XML is still there, with every segment, for logging' ($d.xml -match '<OBX>' -and $d.xml -match '<PID>')
    $s = Get-Segments $d.ack
    Check 'ACK: MSA|AE with the first error in MSA-3, then one ERR per error' ($s[1] -like 'MSA|AE|NWD000512|Required segment PV1 is missing*' -and @($s | Where-Object { $_ -like 'ERR|*' }).Count -eq @($d.errors | Where-Object severity -eq 'Error').Count) ($s -join ' / ')
    Show ($s -join "`n")
}
else {
    Skip 'validation errors (AE with ERR)'
}

Step '3. AR: the message cannot be processed at all.'
$r = Send 'receive' 'messages/unknown-structure.hl7'
$s = Get-Segments $r.Text
Check 'ORU^R01 has no schema here: AR, ERR 200 Unsupported message type' ($s[1] -eq 'MSA|AR|NWD000513|No schema found for message structure ORU_R01, version 2.5.' -and $s[2] -like 'ERR||MSH^1^9^1|200^Unsupported message type^HL70357|E*') ($s -join ' / ')
$r = Send 'receive' 'messages/version-2-4.hl7' 'schemaless=true'
$s = Get-Segments $r.Text
Check 'MSH-12 2.4 is not in supportedVersions (2.5): AR, even with &schemaless=true' ($s[1] -eq "MSA|AR|NWD000514|HL7 version '2.4' is not supported.") ($s -join ' / ')
Check 'the ACK is in the message''s version, so ERR has the v2.4 layout: ERR-1 MSH^1^12^203 (Unsupported version id)' ($s[0] -like '*|ACK^A01^ACK|*|P|2.4' -and $s[2] -eq 'ERR|MSH^1^12^203&Unsupported version id&HL70357') ($s -join ' / ')
Show ($s -join "`n")
$r = Invoke-Hl7Workflow 'inspect' -Body 'PID|1||900599^^^NWD^MR' -BaseUrl $BaseUrl
Write-Host "  POST inspect (no MSH segment) -> HTTP $($r.Status)"
Check 'no MSH: AR, with no ACK, since there is no MSH to answer' ($r.Status -eq 200 -and $r.Body.ackCode -eq 'AR' -and -not $r.Body.ack -and $r.Body.errors[0].message -match 'MSH') "($($r.Status) $($r.Body | ConvertTo-Json -Depth 5 -Compress))"

Step '4. A Z segment (ZPV) that no schema defines is kept.'
if ($schemas) {
    $r = Send 'inspect' 'messages/adt-a01-with-z-segment.hl7'
    $d = $r.Body
    Check 'AA, with a warning (not an error) that ZPV is not in the schema' ($d.ackCode -eq 'AA' -and $d.errors.Count -eq 1 -and $d.errors[0].severity -eq 'Warning' -and $d.errors[0].message -match 'ZPV') "($($d.ackCode) $($d.errors | ConvertTo-Json -Compress))"
}
else {
    $r = Send 'inspect' 'messages/adt-a01-with-z-segment.hl7' 'schemaless=true'
    $d = $r.Body
    Check 'no schema (&schemaless=true): AA, and no warning, since nothing is checked' ($d.ackCode -eq 'AA' -and @($d.errors).Count -eq 0) "($($d.ackCode) $($d.errors | ConvertTo-Json -Compress))"
}
[xml]$x = $d.xml
Check 'ZPV is in the XML with generic names: ZPV_2_0 is VIP, ZPV_3 is QUIET' ($x.SelectSingleNode('/*/ZPV/ZPV_2/ZPV_2_0').InnerText -eq 'VIP' -and $x.SelectSingleNode('/*/ZPV/ZPV_3').InnerText -eq 'QUIET')
Show (($d.xml -split "`n" | Select-String -Pattern '<ZPV>' -Context 0, 7 | Out-String).Trim())

Step '5. Enhanced mode: a commit ACK now, an application ACK when MSH-16 asks for one.'
$r = Send 'enhanced-ack' 'messages/enhanced.hl7'
$d = $r.Body
Check 'MSH-15 AL, MSH-16 AL: commit ACK CA' ($d.acceptAckType -eq 'AL' -and $d.applicationAckType -eq 'AL' -and $d.commitAckCode -eq 'CA' -and (Get-Segments $d.commitAck)[1] -eq 'MSA|CA|NWD000521') "($($r.Text))"
Check 'and an application ACK AA' ((Get-Segments $d.applicationAck)[1] -eq 'MSA|AA|NWD000521') "($($d.applicationAck))"
Show "$($d.commitAck)`n$($d.applicationAck)"
$r = Send 'enhanced-ack' 'messages/enhanced-missing-pv1.hl7'
$d = $r.Body
if ($schemas) {
    Check 'MSH-16 ER and no PV1: commit ACK CE with the error' ($d.commitAckCode -eq 'CE' -and (Get-Segments $d.commitAck)[1] -like 'MSA|CE|NWD000522|Required segment PV1 is missing*') "($($r.Text))"
    Check 'ER means "on error only", so an application ACK AE is sent' ((Get-Segments $d.applicationAck)[1] -like 'MSA|AE|NWD000522*') "($($d.applicationAck))"
}
else {
    Check 'no schema: commit ACK CA; MSH-16 ER and no error, so no application ACK' ($d.commitAckCode -eq 'CA' -and -not $d.applicationAck) "($($r.Text))"
}

Complete-Demo

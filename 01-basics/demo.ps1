<#
.SYNOPSIS
    Decodes, encodes, acknowledges and round-trips an ADT^A01, and checks every result. Start the sample first with
    ./run.ps1. Steps that need the ADT_A01 schema are skipped (not failed) when it hasn't been generated.
    Exits with 1 when a check fails.
#>
[CmdletBinding()]
param([string]$BaseUrl = 'http://localhost:7201')

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/Hl7Sample.psm1') -Force
Set-Location $PSScriptRoot
$schemas = Initialize-Demo -App $PSScriptRoot -BaseUrl $BaseUrl -Schemas ADT_A01

function Send([string]$workflow, [string]$file, [string]$query = '') {
    $r = Invoke-Hl7Workflow $workflow $file -BaseUrl $BaseUrl -Query $query
    Write-Host "  POST $workflow $(Split-Path $file -Leaf)$(if ($query) { " ?$query" }) -> HTTP $($r.Status)"
    $r
}

function SendJson([string]$workflow, [hashtable]$body) {
    $r = Invoke-Hl7Workflow $workflow -Body ($body | ConvertTo-Json) -ContentType 'application/json' -BaseUrl $BaseUrl
    Write-Host "  POST $workflow $(($body.Keys | Sort-Object) -join ', ') -> HTTP $($r.Status)"
    $r
}

$adt = Get-Content 'messages/adt-a01.hl7' -Raw

Step '1. Decode: ER7 to one XML document, validated against ADT_A01_25, and an ACK.'
if ($schemas) {
    $r = Send 'decode' 'messages/adt-a01.hl7'
    $d = $r.Body
    Check 'HTTP 200, success, ACK code AA' ($r.Status -eq 200 -and $d.success -eq $true -and $d.ackCode -eq 'AA') "($($r.Status) $($d.ackCode))"
    Check 'the schema was picked from MSH-9 (ADT_A01) and MSH-12 (2.5)' ($d.messages[0].schema -eq 'ADT_A01_25.xsd#ADT_A01_25') "($($d.messages[0].schema))"
    Check 'messages[0] has the header fields: type, event, version, control id, sender' (
        $d.messages[0].messageType -eq 'ADT' -and $d.messages[0].triggerEvent -eq 'A01' -and $d.messages[0].version -eq '2.5' -and
        $d.messages[0].controlId -eq 'NWD000101' -and $d.messages[0].sendingApplication -eq 'NWD-ADT')
    [xml]$x = $d.xml
    $ns = [System.Xml.XmlNamespaceManager]::new($x.NameTable); $ns.AddNamespace('ns0', 'http://lambogenius.com/HealthCare/HL7/2X')
    Check 'one document: root ADT_A01_25 with MSH as its first child' ($x.DocumentElement.LocalName -eq 'ADT_A01_25' -and $x.DocumentElement.FirstChild.LocalName -eq 'MSH')
    Check 'names from the schema: PID_5_PatientName/XPN_0_FamilyName/FN_0_Surname is SAMPLE' (
        $x.SelectSingleNode('/ns0:ADT_A01_25/PID/PID_5_PatientName/XPN_0_FamilyName/FN_0_Surname', $ns).InnerText -eq 'SAMPLE')
    Check 'OBX-5 is typed by OBX-2 (NM): 170, no warnings' ($x.SelectSingleNode('//OBX/OBX_5_ObservationValue').InnerText -eq '170' -and @($d.errors).Count -eq 0)
    $ack = Get-Segments $d.ack
    Check 'ACK: MSH back to the sender (MSH-3/4 and 5/6 swapped), ACK^A01^ACK, MSA|AA|NWD000101' (
        $ack[0] -like 'MSH|^~\&|LAMBO-EMR|LAMBO CLINIC|NWD-ADT|NORTHWIND GENERAL|*|ACK^A01^ACK|*|P|2.5' -and $ack[1] -eq 'MSA|AA|NWD000101') ($ack -join ' / ')
    Show (($d.xml -split "`n" | Select-Object -First 12) -join "`n")
    Show '...'
}
else {
    $r = Send 'decode' 'messages/adt-a01.hl7'
    Check 'with no schema the message is refused: HTTP 200, ACK code AR, error 200 "Unsupported message type"' (
        $r.Status -eq 200 -and $r.Body.ackCode -eq 'AR' -and $r.Body.errors[0].code -eq '200' -and (Get-Segments $r.Body.ack)[1] -like 'MSA|AR|NWD000101|No schema found*') "($($r.Status) $($r.Body.ackCode))"
    Skip 'decode with the ADT_A01_25 schema'
}

Step '2. Decode with no schema (allowSchemaless): generic names, and still an AA.'
$r = Send 'decode-schemaless' 'messages/adt-a01.hl7'
$d = $r.Body
if ($schemas) {
    Check 'a schema exists, so allowSchemaless changes nothing: ADT_A01_25 is used' ($d.success -eq $true -and $d.messages[0].schema -eq 'ADT_A01_25.xsd#ADT_A01_25') "($($d.messages[0].schema))"
}
else {
    Check 'no schema, but accepted: AA, root ADT_A01 (from MSH-9.3)' ($d.success -eq $true -and $d.ackCode -eq 'AA' -and ([xml]$d.xml).DocumentElement.LocalName -eq 'ADT_A01') "($($d.ackCode))"
}
# A made-up message type has no schema in either mode, so this part always runs schemaless.
$z = $adt.Replace('ADT^A01^ADT_A01', 'ZRG^Z01')
$r = Invoke-Hl7Workflow 'decode-schemaless' -Body $z -BaseUrl $BaseUrl
Write-Host "  POST decode-schemaless (MSH-9 changed to ZRG^Z01, which no schema defines) -> HTTP $($r.Status)"
$d = $r.Body
[xml]$x = $d.xml
Check 'success, ACK code AA, no schema' ($d.success -eq $true -and $d.ackCode -eq 'AA' -and -not $d.messages[0].schema) "($($d.ackCode) $($d.messages[0].schema))"
Check 'root named after MSH-9: ZRG_Z01, MSH first' ($x.DocumentElement.LocalName -eq 'ZRG_Z01' -and $x.DocumentElement.FirstChild.LocalName -eq 'MSH')
Check 'fields 1-based, components 0-based: PID/PID_5/PID_5_0 is SAMPLE, PID_5_1 is ALEX' (
    $x.SelectSingleNode('/*/PID/PID_5/PID_5_0').InnerText -eq 'SAMPLE' -and $x.SelectSingleNode('/*/PID/PID_5/PID_5_1').InnerText -eq 'ALEX')
Check 'a single-component field is plain text: PID/PID_8 is F' ($x.SelectSingleNode('/*/PID/PID_8').InnerText -eq 'F')
Show (($d.xml -split "`n" | Select-String -Pattern '<PID_5>' -Context 0, 4 | Out-String).Trim())

Step '3. Encode: the XML of an ADT^A08 (messages/adt-a08.xml) to ER7.'
$r = Send 'encode' 'messages/adt-a08.xml'
$s = Get-Segments $r.Text
Check 'HTTP 200, text/plain, four segments ending with CR' ($r.Status -eq 200 -and $r.ContentType -like 'text/plain*' -and $s.Count -eq 4 -and $r.Text.EndsWith("`r") -and $r.Text -notmatch "`n") "($($r.Status) $($r.Text))"
Check 'MSH from MSH_1/MSH_2, positions from the element numbers' ($s[0] -eq 'MSH|^~\&|LAMBO-EMR|LAMBO CLINIC|NWD-ADT|NORTHWIND GENERAL|20261028101500||ADT^A08^ADT_A01|LMB000201|P|2.5') $s[0]
Check '& in the data is escaped as \T\; repeated PID_13 elements become ~' ($s[2] -eq 'PID|||900101^^^NWD^MR||SAMPLE-O''NEIL^ALEX||||||CORNER OF KING \T\ QUEEN^^SPRINGFIELD||555-0199~555-0142') $s[2]
Check 'empty trailing fields trimmed: PV1-44 is the last field' ($s[3] -eq ('PV1||I' + ('|' * 42) + '20261028092500')) $s[3]
Show ($s -join "`n")
if ($schemas) {
    $r = Send 'encode' 'messages/adt-a08.xml' 'validate=true'
    Check 'with &validate=true: valid against ADT_A01_25, HTTP 200' ($r.Status -eq 200) "($($r.Status) $($r.Text))"
    $bad = (Get-Content 'messages/adt-a08.xml' -Raw) -replace '(?s)\s*<PID_5_PatientName>.*?</PID_5_PatientName>', ''
    $r = Invoke-Hl7Workflow 'encode' -Body $bad -ContentType 'application/xml' -BaseUrl $BaseUrl -Query 'validate=true'
    Write-Host "  POST encode (PID_5_PatientName removed) ?validate=true -> HTTP $($r.Status)"
    Check 'without PID-5 (required): HTTP 400, error 102 at PID, nothing encoded' ($r.Status -eq 400 -and $r.Body[0].code -eq '102' -and $r.Body[0].message -match 'PID_5_PatientName') "($($r.Status) $($r.Text))"
}
else {
    Skip 'encode with &validate=true against ADT_A01_25'
}

Step '4. Create ACK: acknowledge a message after processing it.'
$r = SendJson 'create-ack' @{ message = $adt }
$s = Get-Segments $r.Text
Check 'default code AA: MSA|AA|NWD000101' ($r.Status -eq 200 -and $s[1] -eq 'MSA|AA|NWD000101') "($($r.Status) $($r.Text))"
$r = SendJson 'create-ack' @{ message = $adt; ackCode = 'AE'; errorMessage = 'Unknown attending doctor 1234' }
$s = Get-Segments $r.Text
Check 'AE with the text in MSA-3 and an ERR segment (207, HL7 table 0357)' ($s[1] -eq 'MSA|AE|NWD000101|Unknown attending doctor 1234' -and $s[2] -eq 'ERR|||207^Application internal error^HL70357|E||||Unknown attending doctor 1234') ($s -join ' / ')
Show ($s -join "`n")
$r = SendJson 'create-ack' @{ message = $adt; ackCode = 'XX' }
Check 'an unknown ackCode: HTTP 400 with the reason' ($r.Status -eq 400 -and $r.Body[0].message -match "Invalid ackCode 'XX'") "($($r.Status) $($r.Text))"
$r = SendJson 'create-ack' @{ message = 'PID|1||900101' }
Check 'no MSH: HTTP 400' ($r.Status -eq 400 -and $r.Body[0].message -match 'MSH') "($($r.Status) $($r.Text))"

Step '5. Round trip: decode, encode again, application ACK.'
$r = Send 'round-trip' 'messages/adt-a01.hl7'
$d = $r.Body
Check 'decoded and encoded, ER7 identical to the input' ($d.decodeSuccess -eq $true -and $d.encodeSuccess -eq $true -and $d.roundTripIdentical -eq $true) "($($r.Text))"
Check "schema: $(if ($schemas) { 'ADT_A01_25' } else { 'none (allowSchemaless)' })" ($(if ($schemas) { $d.schema -eq 'ADT_A01_25.xsd#ADT_A01_25' } else { -not $d.schema })) "($($d.schema))"
Check 'application ACK AA' ((Get-Segments $d.applicationAck)[1] -eq 'MSA|AA|NWD000101') $d.applicationAck
$custom = $adt.Replace('|', '#').Replace('^', '*').Replace('~', '@').Replace('\', '!').Replace('&', '%')
$r = Invoke-Hl7Workflow 'round-trip' -Body $custom -BaseUrl $BaseUrl
Write-Host "  POST round-trip (the same message with the delimiters #*@!%) -> HTTP $($r.Status)"
$d = $r.Body
Check 'other delimiters: identical round trip, and the ACK uses them too' ($d.roundTripIdentical -eq $true -and (Get-Segments $d.applicationAck)[1] -eq 'MSA#AA#NWD000101') "($($r.Text))"

Complete-Demo

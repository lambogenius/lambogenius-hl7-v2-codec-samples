<#
.SYNOPSIS
    Decodes an ADT^A01 to JSON, encodes JSON back to ER7, and changes a field in the JSON with workflow expressions,
    checking every result. Start the sample first with ./run.ps1. Steps that need the ADT_A01 schema are skipped
    (not failed) when it hasn't been generated. Exits with 1 when a check fails.
#>
[CmdletBinding()]
param([string]$BaseUrl = 'http://localhost:7202')

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/Hl7Sample.psm1') -Force
Set-Location $PSScriptRoot
$schemas = Initialize-Demo -App $PSScriptRoot -BaseUrl $BaseUrl -Schemas ADT_A01

function Send([string]$workflow, [string]$file, [string]$query = '') {
    $r = Invoke-Hl7Workflow $workflow $file -BaseUrl $BaseUrl -Query $query
    Write-Host "  POST $workflow $(Split-Path $file -Leaf)$(if ($query) { " ?$query" }) -> HTTP $($r.Status)"
    $r
}

$er7 = Get-Content 'messages/adt-a01.hl7' -Raw
function Same([string]$a, [string]$b) { ($a -replace "[`r`n]+", "`n").Trim() -ceq ($b -replace "[`r`n]+", "`n").Trim() }

Step '1. Decode to JSON (outputFormat json).'
$r = Send 'to-json' 'messages/adt-a01.hl7'
Check 'HTTP 200, outputFormat json, xml left empty' ($r.Status -eq 200 -and $r.Body.outputFormat -eq 'json' -and $r.Body.xmlIsEmpty -eq $true) "($($r.Status) $($r.Text))"
$decoded = $r.Body.message
if ($schemas) {
    $m = $decoded.ADT_A01_25
    Check 'schema ADT_A01_25; the JSON has the same names as the XML' ($r.Body.schema -eq 'ADT_A01_25.xsd#ADT_A01_25' -and $m.MSH.MSH_10_MessageControlID -eq 'NWD000201') "($($r.Body.schema))"
    Check 'what the schema lets repeat is always an array, even with one value: PID_3, PID_5, OBX' (
        $m.PID.PID_3_PatientIdentifierList -is [array] -and $m.PID.PID_5_PatientName -is [array] -and $m.OBX -is [array] -and $m.PID.PID_3_PatientIdentifierList.Count -eq 1)
    Check 'what cannot repeat is an object or a string: PV1_3 and PV1_2' ($m.PV1.PV1_3_AssignedPatientLocation.PL_1_Room -eq '301' -and $m.PV1.PV1_2_PatientClass -eq 'I')
    Check 'values are always strings, so 0-padded codes keep their zeros: PV1_19 is "V000501"' ($m.PV1.PV1_19_VisitNumber.CX_0_IDNumber -ceq 'V000501')
    Show ($m.PID | ConvertTo-Json -Depth 10)
}
else {
    $m = $decoded.ADT_A01
    Check 'no schema (allowSchemaless): root ADT_A01, generic names' ($r.Body.schema -eq $null -and $m.MSH.MSH_10 -eq 'NWD000201' -and $m.PID.PID_5.PID_5_0 -eq 'SAMPLE') "($($r.Text))"
    Check 'with no schema, only actual repetitions are arrays: PID_3 and OBX are objects here' ($m.PID.PID_3 -isnot [array] -and $m.OBX -isnot [array] -and $m.PID.PID_3.PID_3_0 -eq '900111')
    Show ($m.PID | ConvertTo-Json -Depth 10)
    Skip 'JSON with the ADT_A01_25 names and arrays'
}

Step '2. Encode the JSON back to ER7.'
$r = Invoke-Hl7Workflow 'from-json' -Body ($decoded | ConvertTo-Json -Depth 30) -ContentType 'application/json' -BaseUrl $BaseUrl
Write-Host "  POST from-json (the JSON from step 1) -> HTTP $($r.Status)"
Check 'HTTP 200, the same ER7 as messages/adt-a01.hl7' ($r.Status -eq 200 -and (Same $r.Text $er7)) "($($r.Status) $($r.Text))"
$r = Send 'from-json' 'messages/adt-a01.json'
Check 'messages/adt-a01.json (the JSON form with the schema''s names) encodes to the same ER7, with or without the schema' ($r.Status -eq 200 -and (Same $r.Text $er7)) "($($r.Status) $($r.Text))"
if ($schemas) {
    $r = Send 'from-json' 'messages/adt-a01.json' 'validate=true'
    Check 'and it is valid against ADT_A01_25 (&validate=true)' ($r.Status -eq 200) "($($r.Status) $($r.Text))"
    $json = Get-Content 'messages/adt-a01.json' -Raw | ConvertFrom-Json
    $json.ADT_A01_25.PID.PSObject.Properties.Remove('PID_3_PatientIdentifierList')
    $r = Invoke-Hl7Workflow 'from-json' -Body ($json | ConvertTo-Json -Depth 30) -ContentType 'application/json' -BaseUrl $BaseUrl -Query 'validate=true'
    Write-Host "  POST from-json (PID_3 removed) ?validate=true -> HTTP $($r.Status)"
    Check 'without PID-3 (required): HTTP 400, error 102' ($r.Status -eq 400 -and $r.Body[0].code -eq '102') "($($r.Status) $($r.Text))"
}
else {
    Skip 'JSON validated against ADT_A01_25'
}

Step '3. Change fields in the JSON (a bed move, sent on as an A08) and encode it.'
$r = Send 'transfer-patient' 'messages/adt-a01.hl7' 'ward=WARD7&room=702&bed=A'
if ($schemas) {
    $s = Get-Segments $r.Text
    Check 'HTTP 200: the changed JSON is valid against ADT_A01_25 and encoded' ($r.Status -eq 200 -and $s.Count -eq 5) "($($r.Status) $($r.Text))"
    Check 'MSH-9 ADT^A08^ADT_A01, MSH-10 NWD000201-T, the rest of MSH unchanged' ($s[0] -eq 'MSH|^~\&|NWD-ADT|NORTHWIND GENERAL|LAMBO-EMR|LAMBO CLINIC|20261028093000||ADT^A08^ADT_A01|NWD000201-T|P|2.5') $s[0]
    Check 'EVN-1 A08' ($s[1] -eq 'EVN|A08|20261028092500') $s[1]
    Check 'PV1-3 is WARD7^702^A^NWD (facility kept); every other field in its place' ($s[3] -eq 'PV1|1|I|WARD7^702^A^NWD||||1234^EXAMPLE^CHRIS^^^DR|||MED|||||||||V000501') $s[3]
    Check 'PID and OBX unchanged' ($s[2] -eq (Get-Segments $er7)[2] -and $s[4] -eq (Get-Segments $er7)[4])
    Show ($s -join "`n")
}
else {
    Check 'with no schema the workflow refuses the message: HTTP 422, AR' ($r.Status -eq 422 -and $r.Body.ackCode -eq 'AR') "($($r.Status) $($r.Text))"
    Skip 'the bed move, which uses the ADT_A01_25 names'
}

Complete-Demo

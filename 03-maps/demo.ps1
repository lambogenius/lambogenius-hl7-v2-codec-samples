<#
.SYNOPSIS
    Maps a decoded ADT^A01 to a patient summary with the Transform XML action and reads fields with xpath(), and
    checks the results. Start the sample first with ./run.ps1. With the ADT_A01 schema the map for its names is used;
    without it, the map for generic names. Exits with 1 when a check fails.
#>
[CmdletBinding()]
param([string]$BaseUrl = 'http://localhost:7203')

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/Hl7Sample.psm1') -Force
Set-Location $PSScriptRoot
$schemas = Initialize-Demo -App $PSScriptRoot -BaseUrl $BaseUrl -Schemas ADT_A01

function Summary($r) { [xml]($r.Text.TrimStart([char]0xFEFF)) }

$expectedMap = if ($schemas) { 'patient-summary.xslt' } else { 'patient-summary-generic.xslt' }

Step "1. Decode, then Transform XML with $expectedMap."
$r = Invoke-Hl7Workflow 'patient-summary' 'messages/adt-a01.hl7' -BaseUrl $BaseUrl
Write-Host "  POST patient-summary adt-a01.hl7 -> HTTP $($r.Status)"
Check "HTTP 200, application/xml, made with $expectedMap" ($r.Status -eq 200 -and $r.ContentType -like 'application/xml*' -and "$($r.Headers['x-map'])" -eq $expectedMap) "($($r.Status) $($r.Headers['x-map']) $($r.Text))"
$s = (Summary $r).PatientSummary
Check 'MSH-10 and MSH-9.2: NWD000401, A01' ($s.ControlId -eq 'NWD000401' -and $s.Event -eq 'A01')
Check 'the MR number picked from the repeating PID-3 by its type code: 900301' ($s.MedicalRecordNumber -eq '900301') $s.MedicalRecordNumber
Check 'name, birth date reformatted, sex: SAMPLE, TAYLOR, 1992-06-30, M' ($s.FamilyName -eq 'SAMPLE' -and $s.GivenName -eq 'TAYLOR' -and $s.BirthDate -eq '1992-06-30' -and $s.Sex -eq 'M')
Check 'bed and attending doctor from PV1-3 and PV1-7: WARD5 512-B, DR PAT DEMO' ($s.Location -eq 'WARD5 512-B' -and $s.AttendingDoctor -eq 'DR PAT DEMO') "($($s.Location) / $($s.AttendingDoctor))"
$obs = @($s.Observations.Observation)
Check 'two observations with code, units and value' ($obs.Count -eq 2 -and $obs[0].code -eq 'HT' -and $obs[0].units -eq 'cm' -and $obs[0].'#text' -eq '182' -and $obs[1].'#text' -eq '79.5')
Check 'two procedures (PR1)' ($s.Procedures.count -eq '2' -and @($s.Procedures.Procedure)[1].code -eq 'DRN')
Check 'the Z segment ZPV is mapped too: Flag VIP' ($s.Flag -eq 'VIP') $s.Flag
Show $r.Text.TrimStart([char]0xFEFF)

Step '2. xpath() on the decoded XML, in the same workflow.'
Check 'PV1-2 (patient class) is I, matched by its number' ("$($r.Headers['x-patient-class'])" -eq 'I') "$($r.Headers['x-patient-class'])"
Check 'count(/*/OBX) is 2' ("$($r.Headers['x-observation-count'])" -eq '2') "$($r.Headers['x-observation-count'])"

Step '3. The same message as another version (MSH-12 2.3), which has no schema here.'
$old = (Get-Content 'messages/adt-a01.hl7' -Raw).Replace('|P|2.5', '|P|2.3')
$r = Invoke-Hl7Workflow 'patient-summary' -Body $old -BaseUrl $BaseUrl
Write-Host "  POST patient-summary (MSH-12 changed to 2.3) -> HTTP $($r.Status)"
$s = (Summary $r).PatientSummary
Check 'decoded schemaless and mapped with patient-summary-generic.xslt' ($r.Status -eq 200 -and "$($r.Headers['x-map'])" -eq 'patient-summary-generic.xslt') "($($r.Status) $($r.Headers['x-map']))"
Check 'same summary: SAMPLE, 900301, WARD5 512-B, 2 procedures, VIP' ($s.FamilyName -eq 'SAMPLE' -and $s.MedicalRecordNumber -eq '900301' -and $s.Location -eq 'WARD5 512-B' -and $s.Procedures.count -eq '2' -and $s.Flag -eq 'VIP')
Check 'the xpath() fields work the same' ("$($r.Headers['x-patient-class'])" -eq 'I' -and "$($r.Headers['x-observation-count'])" -eq '2')

Complete-Demo

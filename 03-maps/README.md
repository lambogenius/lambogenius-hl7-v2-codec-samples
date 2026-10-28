# 03 · Maps

The decoded XML works with the Logic Apps built-in **Transform XML** action (XSLT maps in `Artifacts/Maps`, which is
also what the Data Mapper produces) and with the `xpath()` expression.

| Workflow | Actions | Request → response |
|---|---|---|
| `patient-summary` | Decode → Transform XML, and `xpath()` | ER7 → a `PatientSummary` XML document; headers `x-map`, `x-patient-class` and `x-observation-count` |

| Map | For |
|---|---|
| `Artifacts/Maps/patient-summary.xslt` | XML decoded with the ADT_A01 schema generated from v2.5: root `ns0:ADT_A01_25`, names such as `PID_5_PatientName/XPN_0_FamilyName/FN_0_Surname`, groups `ADT_A01_PROCEDURE` |
| `Artifacts/Maps/patient-summary-generic.xslt` | XML decoded with no schema: names such as `PID_5/PID_5_0`, no groups |

The workflow picks the map: the generic one when Decode found no schema (`allowSchemaless` is on), the other one
otherwise. Transform XML takes the map name from an expression. Both maps give the same summary.

## Run it

See the [prerequisites](../README.md#prerequisites).

```powershell
./run.ps1 -V2XmlFolder C:\hl7\v2xml\2.5   # or just ./run.ps1; Logic App on http://localhost:7203
./demo.ps1                                # in a second window
./send.ps1 patient-summary messages/adt-a01.hl7
```

Every step runs with or without the schema. The demo also sends the message as v2.3, which has no schema here, so it
goes through the generic map in both cases.

## The map

`messages/adt-a01.hl7` (two identifiers in PID-3, two OBX, two PR1 and a Z segment) becomes:

```xml
<PatientSummary mappedWith="schema">
  <ControlId>NWD000401</ControlId>
  <Event>A01</Event>
  <MedicalRecordNumber>900301</MedicalRecordNumber>
  <FamilyName>SAMPLE</FamilyName>
  <GivenName>TAYLOR</GivenName>
  <BirthDate>1992-06-30</BirthDate>
  <Sex>M</Sex>
  <Location>WARD5 512-B</Location>
  <AttendingDoctor>DR PAT DEMO</AttendingDoctor>
  <Observations>
    <Observation code="HT" units="cm">182</Observation>
    <Observation code="WT" units="kg">79.5</Observation>
  </Observations>
  <Procedures count="2">
    <Procedure code="APPX">Appendectomy</Procedure>
    <Procedure code="DRN">Abdominal drain</Procedure>
  </Procedures>
  <Flag>VIP</Flag>
</PatientSummary>
```

- **Namespaces.** Only the message root is in a namespace (the schema's `targetNamespace`,
  `http://lambogenius.com/HealthCare/HL7/2X`). Declare it with a prefix and match `/ns0:ADT_A01_25`; segments, fields
  and components have no namespace. The generic map matches `/*`, so the root's name and namespace don't matter.
- **Repetitions.** PID-3 repeats; `PID_3_PatientIdentifierList[CX_4_IdentifierTypeCode = 'MR']` picks the medical
  record number by its type code.
- **Groups.** With the schema, each PR1 is in an `ADT_A01_PROCEDURE` group; without it, PR1 segments sit directly
  under the root.
- **Z segments.** No schema defines `ZPV`, so its names are generic in both maps (`ZPV_2_0`). It stays where it was
  in the message: after the last PR1, which with the schema puts it inside the last `ADT_A01_PROCEDURE` group. The maps
  use `//ZPV` to find it wherever it is.

## xpath()

```
@xpath(xml(body('Decode_HL7')?['xml']), 'string(/*/PV1/*[local-name() = ''PV1_2'' or starts-with(local-name(), ''PV1_2_'')])')
```

Matching a field by its number (`PV1_2`, or `PV1_2_` followed by the description) works with the schema's names and
with the generic ones, and doesn't depend on the root's name. `count(/*/OBX)` counts the observations.

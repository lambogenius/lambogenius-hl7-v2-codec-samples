# 02 · JSON

Decode can return JSON instead of XML, and Encode reads either. The JSON has the same names as the XML, so the
schema still describes it, and workflow expressions can read and change it directly.

| Workflow | Actions | Request → response |
|---|---|---|
| `to-json` | Decode with `outputFormat: json` | ER7 → `{ "schema": ..., "message": { "ADT_A01_25": { ... } } }` |
| `from-json` | Encode with `inputFormat: json` | the JSON form → ER7 (200) or the errors (400). `&validate=true` validates against the schema first |
| `transfer-patient` | Decode to JSON → expressions → Encode | ER7 with `?ward=&room=&bed=` → an ADT^A08 with the new bed in PV1-3 |

## Run it

See the [prerequisites](../README.md#prerequisites).

```powershell
./run.ps1 -V2XmlFolder C:\hl7\v2xml\2.5   # or just ./run.ps1; Logic App on http://localhost:7202
./demo.ps1                                # in a second window
./send.ps1 to-json messages/adt-a01.hl7
./send.ps1 from-json messages/adt-a01.json -Query validate=true
./send.ps1 transfer-patient messages/adt-a01.hl7 -Query "ward=WARD7&room=702&bed=A"
```

Without the schema, `to-json` and `from-json` still run (with generic names); `transfer-patient` answers 422 with AR,
because its expressions use the schema's names.

## The JSON

```json
{ "ADT_A01_25": {
    "MSH": { "MSH_1_FieldSeparator": "|", "MSH_2_EncodingCharacters": "^~\\&", ...,
             "MSH_10_MessageControlID": "NWD000201", ... },
    "PID": { "PID_3_PatientIdentifierList": [ { "CX_0_IDNumber": "900111", ..., "CX_4_IdentifierTypeCode": "MR" } ],
             "PID_5_PatientName": [ { "XPN_0_FamilyName": { "FN_0_Surname": "SAMPLE" }, "XPN_1_GivenName": "JORDAN", ... } ],
             "PID_8_AdministrativeSex": "F", ... },
    "PV1": { "PV1_2_PatientClass": "I",
             "PV1_3_AssignedPatientLocation": { "PL_0_PointOfCare": "WARD3", "PL_1_Room": "301", "PL_2_Bed": "A", ... },
             "PV1_19_VisitNumber": { "CX_0_IDNumber": "V000501" }, ... },
    "OBX": [ { ... } ] } }
```

- An element with children is an object; one without is a **string**, never a number, so `V000501` and `"01"`
  keep their zeros.
- **Anything the schema lets repeat is an array**, even with one value (`PID_3`, `PID_5`, `OBX`), so the shape doesn't
  depend on the message: `@first(...?['PID_5_PatientName'])?['XPN_1_GivenName']` always works.
- With no schema (`allowSchemaless`), the names are generic (`PID_5_0`), and only actual repetitions are arrays.

Decode returns the JSON as a string in `body('Decode_HL7')?['json']`; `json(...)` parses it. `xml` is then empty.

## Changing fields

`transfer-patient` moves the patient to another bed and sends the message on as an A08:
- MSH-9.2 and EVN-1 become `A08`, and MSH-10 gets `-T` added;
- PV1-3 becomes the ward, room and bed from the URL, keeping the facility.

Each change is a small object (`MSH_changes`, `EVN_changes`, `PV1_changes`), merged into its segment with `union()`,
and the changed segments are merged into the message the same way:

```
"MSH": "@union(outputs('Message')?['MSH'], outputs('MSH_changes'))"
```

**Use `union()`, not `setProperty()`.** Encode reads segments in the order of the JSON properties, and the schema
expects fields in order too. `union()` replaces a value where it is; `setProperty()` removes the property and adds it
at the end, so `MSH` would come after `PID` ("The first segment in the XML must be MSH"), and a changed field after
the others (XSD error 102).

The result is validated against `ADT_A01_25` and encoded:

```
MSH|^~\&|NWD-ADT|NORTHWIND GENERAL|LAMBO-EMR|LAMBO CLINIC|20261028093000||ADT^A08^ADT_A01|NWD000201-T|P|2.5
EVN|A08|20261028092500
PID|1||900111^^^NWD^MR||SAMPLE^JORDAN^K||19850214|F|||100 EXAMPLE ROAD^^SPRINGFIELD^ON^A1A 1A1^CA||555-0100
PV1|1|I|WARD7^702^A^NWD||||1234^EXAMPLE^CHRIS^^^DR|||MED|||||||||V000501
OBX|1|NM|HT^Body height^L||170|cm^centimeter^UCUM|||||F
```

# 01 · Basics

The three actions, one workflow each, plus a round trip and a decode with no schema:

| Workflow | Actions | Request → response |
|---|---|---|
| `decode` | Decode | ER7 → everything Decode returns, as JSON: `success`, `ackCode`, `xml`, `ack`, `messages[]`, `errors[]` |
| `decode-schemaless` | Decode with `allowSchemaless` | ER7 → the same, with generic names when no schema fits |
| `encode` | Encode | HL7 XML (or its JSON form) → ER7 (200) or the errors (400). `&validate=true` validates against the schema first |
| `create-ack` | Create ACK | JSON `{ "message": "MSH|...", "ackCode": "AE", "errorMessage": "..." }` → the ACK (200) or the errors (400) |
| `round-trip` | Decode → Encode → Create ACK | ER7 → JSON with both results, `roundTripIdentical` and an application ACK |

`demo.ps1` runs all of them with `messages/adt-a01.hl7` (an ADT^A01, admit a patient) and `messages/adt-a08.xml`
(an ADT^A08, update patient information, as XML).

## Run it

See the [prerequisites](../README.md#prerequisites).

```powershell
./run.ps1 -V2XmlFolder C:\hl7\v2xml\2.5   # or just ./run.ps1; Logic App on http://localhost:7201
./demo.ps1                                # in a second window
./send.ps1 decode messages/adt-a01.hl7
./send.ps1 encode messages/adt-a08.xml -Query validate=true
./send.ps1 create-ack messages/adt-a01.hl7 -AckCode AE -ErrorMessage 'Unknown attending doctor'
```

Without the schema, the steps that decode or validate against `ADT_A01_25` are skipped; the others run.

## Decode

```
MSH|^~\&|NWD-ADT|NORTHWIND GENERAL|LAMBO-EMR|LAMBO CLINIC|20261028093000||ADT^A01^ADT_A01|NWD000101|P|2.5
EVN|A01|20261028092500
PID|1||900101^^^NWD^MR||SAMPLE^ALEX^J||19850214|F|||100 EXAMPLE ROAD^^SPRINGFIELD^ON^A1A 1A1^CA||555-0100
...
```

becomes one XML document. `MSH` is the first child of the message root, so the header and the body are checked
against one schema, `ADT_A01_25.xsd`, chosen from MSH-9 (`ADT_A01`) and MSH-12 (`2.5`):

```xml
<ns0:ADT_A01_25 xmlns:ns0="http://lambogenius.com/HealthCare/HL7/2X">
  <MSH>
    <MSH_1_FieldSeparator>|</MSH_1_FieldSeparator>
    ...
    <MSH_10_MessageControlID>NWD000101</MSH_10_MessageControlID>
  </MSH>
  <EVN>...</EVN>
  <PID>
    <PID_3_PatientIdentifierList>
      <CX_0_IDNumber>900101</CX_0_IDNumber> ...
    </PID_3_PatientIdentifierList>
    <PID_5_PatientName>
      <XPN_0_FamilyName><FN_0_Surname>SAMPLE</FN_0_Surname></XPN_0_FamilyName>
      <XPN_1_GivenName>ALEX</XPN_1_GivenName> ...
```

Fields are numbered from 1, as in HL7 (`PID_5` is PID-5). Components are numbered from 0 (`XPN_0` is XPN.1). Only
the root is in a namespace. OBX-5 takes the type named in OBX-2.

The ACK goes back to the sender: MSH-3/4 and MSH-5/6 are swapped, MSH-9 is `ACK^A01^ACK`, and MSA-2 is the message's
control id:

```
MSH|^~\&|LAMBO-EMR|LAMBO CLINIC|NWD-ADT|NORTHWIND GENERAL|20261028063830-0400||ACK^A01^ACK|20261028103830436873|P|2.5
MSA|AA|NWD000101
```

**No schema.** `decode` answers AR with ERR code 200 ("No schema found for message structure ADT_A01, version 2.5").
`decode-schemaless` sets `allowSchemaless` and decodes it anyway, with generic names and no groups:

```xml
<ns0:ADT_A01 xmlns:ns0="http://microsoft.com/HealthCare/HL7/2X">
  ...
  <PID>
    <PID_5>
      <PID_5_0>SAMPLE</PID_5_0>
      <PID_5_1>ALEX</PID_5_1>
```

A field with one component is plain text (`<PID_8>F</PID_8>`). The demo also sends a made-up message type,
`ZRG^Z01`, which no schema defines: the root is `ZRG_Z01`.

## Encode

`messages/adt-a08.xml` is written with the schema's names. Encode takes the delimiters from `MSH_1` and `MSH_2`, the
positions from the numbers in the element names, escapes the delimiters in the data (`&` becomes `\T\`), writes
repeated elements with `~`, trims empty trailing fields and ends each segment with CR:

```
MSH|^~\&|LAMBO-EMR|LAMBO CLINIC|NWD-ADT|NORTHWIND GENERAL|20261028101500||ADT^A08^ADT_A01|LMB000201|P|2.5
EVN|A08|20261028101400
PID|||900101^^^NWD^MR||SAMPLE-O'NEIL^ALEX||||||CORNER OF KING \T\ QUEEN^^SPRINGFIELD||555-0199~555-0142
PV1||I||||||||||||||||||||||||||||||||||||||||||20261028092500
```

That works with no schema. With `&validate=true`, the XML is first checked against `ADT_A01_25`; the demo removes
PID-5, which is required, and gets 400 with error 102 and nothing encoded.

## Create ACK

Use it when the answer depends on what happens after Decode: decode with `generateAck` off, process the message,
then create the ACK. `AE` and `AR` add an ERR segment with code 207 (table 0357) and the text, which also goes in
MSA-3:

```
MSA|AE|NWD000101|Unknown attending doctor 1234
ERR|||207^Application internal error^HL70357|E||||Unknown attending doctor 1234
```

An unknown `ackCode`, or a message with no MSH, gives 400 and the reason.

## Round trip

Decode, encode the XML again, and create an application ACK: AA when both worked, AE otherwise. This is the
skeleton of "decode, change the XML, encode". Encode's `validateXml` (on by default) needs a schema, so the workflow
turns it on only when Decode found one: `@not(empty(first(body('Decode_HL7')?['messages'])?['schema']))`.

The output is identical to the input, with or without the schema. The demo also sends the message with other
delimiters (`MSH#*@!%`): they come from each message's own MSH-1 and MSH-2, and the ACK uses them too.

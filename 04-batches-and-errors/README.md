# 04 · Batches and errors

What a receiving interface has to answer: batches, messages that are not valid, messages it cannot process, Z
segments, and senders that ask for enhanced-mode acknowledgements.

| Workflow | Actions | Request → response |
|---|---|---|
| `receive` | Decode, a For each over the messages, Response | ER7 or an FHS/BHS batch → the ACK or the batch ACK, as text; headers `x-message-count` and `x-ack-codes`. `&schemaless=true` sets `allowSchemaless` |
| `inspect` | Decode | the same, but returns everything Decode produced, as JSON |
| `enhanced-ack` | Decode → Create ACK | ER7 with MSH-15/16 → JSON with the commit ACK and, when MSH-16 asks for it, the application ACK |

Decode in `receive` and `inspect` sets `supportedVersions` to `2.5`.

| Message | What it is |
|---|---|
| `messages/batch.hl7` | FHS/BHS with three ADT^A01: a valid one, one with MSH-15 `AL` (enhanced mode), one with no PV1 |
| `messages/missing-pv1.hl7` | an ADT^A01 with no PV1, which the schema requires |
| `messages/unknown-structure.hl7` | an ORU^R01, which has no schema in this sample |
| `messages/version-2-4.hl7` | an ADT^A01 that says 2.4 in MSH-12 |
| `messages/adt-a01-with-z-segment.hl7` | an ADT^A01 with a site-defined `ZPV` segment |
| `messages/enhanced.hl7` | MSH-15 `AL`, MSH-16 `AL` |
| `messages/enhanced-missing-pv1.hl7` | MSH-15 `AL`, MSH-16 `ER`, and no PV1 |

## Run it

See the [prerequisites](../README.md#prerequisites).

```powershell
./run.ps1 -V2XmlFolder C:\hl7\v2xml\2.5   # or just ./run.ps1; Logic App on http://localhost:7204
./demo.ps1                                # in a second window
./send.ps1 receive messages/batch.hl7
./send.ps1 receive messages/batch.hl7 -Query schemaless=true
./send.ps1 inspect messages/missing-pv1.hl7
./send.ps1 enhanced-ack messages/enhanced-missing-pv1.hl7
```

Without the schema, the batch is checked with `&schemaless=true` only, and the validation-error step is skipped.

## The batch ACK

One ACK per message, wrapped in FHS/BHS ... BTS/FTS. FHS-12 and BHS-12 refer to the batch's own FHS-11 and BHS-11:

```
FHS|^~\&|LAMBO-EMR|LAMBO CLINIC|NWD-ADT|NORTHWIND GENERAL|20261028...||||20261028...|NWD-F-0001
BHS|^~\&|LAMBO-EMR|LAMBO CLINIC|NWD-ADT|NORTHWIND GENERAL|20261028...||||20261028...|NWD-B-0001
MSH|...|ACK^A01^ACK|...|P|2.5
MSA|AA|NWD000501
MSH|...|ACK^A01^ACK|...|P|2.5
MSA|CA|NWD000502
MSH|...|ACK^A01^ACK|...|P|2.5
MSA|AE|NWD000503|Required segment PV1 is missing.
ERR||PID^3|100^Segment sequence error^HL70357|E||||Required segment PV1 is missing.
BTS|3
FTS|1
```

Each entry of `messages[]` has its own `ackCode`, `success`, `xml` and `errors`; the workflow loops over them to
route the accepted ones. The top-level `ackCode` output is the first message's, so `x-ack-codes` is built from
`messages[]` with a Select action.

With `&schemaless=true` and no schema, the third message is accepted (AA): with no schema, nothing says that PV1 is
required. With the schema, `allowSchemaless` changes nothing.

## The ACK codes

| Code | When | Example |
|---|---|---|
| **AA** | accepted | |
| **AE** | the message doesn't match its schema | no PV1: `ERR` code 100 (segment sequence error); a bad field: 102 (data type error) |
| **AR** | it cannot be processed at all | no schema for ORU_R01: code 200 (unsupported message type); MSH-12 `2.4` with `supportedVersions` `2.5`: code 203 (unsupported version id); no MSH |
| **CA / CE / CR** | the same, in enhanced mode (commit ACKs) | |

HL7 problems never fail the Decode action, and `receive` always answers 200: the ACK is the answer. Every error in
`errors[]` has a `code` from HL7 table 0357, a `severity` (`Error` or `Warning`), a `message` and a `location` such
as `OBX[4]`. The ACK has one ERR segment per error, and MSA-3 holds the first one.

The ACK is written in the message's version. For 2.4 and earlier, ERR uses ERR-1:

```
MSA|AR|NWD000514|HL7 version '2.4' is not supported.
ERR|MSH^1^12^203&Unsupported version id&HL70357
```

A message with no MSH gets AR with no ACK, since there is no header to answer; `receive` then returns an empty body.

## Z segments

`ZPV` is not in any schema. It is kept, with generic names (`ZPV_2_0`), reported as a warning (code 100, severity
`Warning`), and left out of validation, so the message is still AA. Encode writes it back unchanged. Set
`allowUndefinedZSegments` to `false` on Decode to make it an error instead.

## Enhanced mode

MSH-15 (accept acknowledgment type) and MSH-16 (application acknowledgment type) ask for enhanced mode. With
`ackMode` `Auto` (the default), Decode then answers with a **commit ACK**: CA, CE or CR, which says the message was
received. The application ACK comes later, from the system that processes it. `enhanced-ack` reads MSH-16 with
`xpath()` and creates the application ACK with Create ACK when it is wanted:

| MSH-16 | Application ACK |
|---|---|
| `AL` | always |
| `NE` | never |
| `ER` | only when processing failed |
| `SU` | only when it succeeded |

`enhanced.hl7` gets CA and an application AA. `enhanced-missing-pv1.hl7` gets CE and, because of `ER`, an
application AE; with no schema, nothing fails, so it gets CA and no application ACK. In a real interface the
application ACK goes back to the sender on its own connection, for MLLP with the
[HL7 MLLP Connector](https://github.com/lambogenius/lambogenius-mllp-connector-samples).

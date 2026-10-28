# HL7 v2 Codec for Azure Logic Apps: samples

Complete, runnable Azure Logic Apps (Standard) projects that use the **HL7 v2 Codec**, the Lambogenius built-in
connector that decodes HL7 v2 messages (ER7, the pipe-delimited form) to XML or JSON, encodes them back, and creates
ACKs. Its actions are **Decode HL7 message**, **Encode HL7 message** and **Create HL7 acknowledgement**. Decode gives
**one** XML document per message, with `MSH` inside the message root, checked against one XSD.

Each sample folder holds:
- a NuGet-based Logic App project with its workflows (and, in 03, its XSLT maps);
- test messages, all made up: no real patients, facilities or identifiers;
- `run.ps1`, which builds and starts the Logic App, and `demo.ps1`, which runs each step and checks the result;
- `send.ps1`, to send one message yourself.

Documentation: <https://docs.lambogenius.com/hl7-v2-codec>

| Sample | What it shows | Needs the schemas for |
|---|---|---|
| [01 · Basics](01-basics) | Decode (ER7 to one XML document, and the ACK), Encode (XML to ER7, with optional validation), Create ACK, a round trip, and a decode with no schema | decoding and validating against ADT_A01; the rest runs without |
| [02 · JSON](02-json) | Decode to JSON, encode JSON back to ER7, and change fields in the JSON with workflow expressions (a bed move sent on as an A08) | the JSON with the schema's names and arrays, and the bed move |
| [03 · Maps](03-maps) | Decode, then the built-in **Transform XML** action with an XSLT map in `Artifacts/Maps` (a patient summary), and `xpath()` on the decoded XML | nothing: without the schema, a second map for generic names is used |
| [04 · Batches and errors](04-batches-and-errors) | An FHS/BHS batch and its batch ACK, validation errors (AE with ERR), AR for an unknown message type, an unsupported version or no MSH, a Z segment kept, and enhanced-mode commit ACKs (MSH-15/16) with an application ACK | the batch and validation errors; their schemaless counterparts run without |

## Prerequisites

1. **Windows** (the samples are tested on Windows 11) with:
   - the [.NET SDK 8](https://dotnet.microsoft.com/download/dotnet/8.0);
   - [Azure Functions Core Tools 4](https://learn.microsoft.com/azure/azure-functions/functions-run-local): `npm install -g azure-functions-core-tools@4`;
   - [Azurite](https://learn.microsoft.com/azure/storage/common/storage-use-azurite): `npm install -g azurite`;
   - [PowerShell 7.2 or later](https://aka.ms/powershell).
2. **The HL7 v2 Codec package.** Sign in at <https://lambogenius.com/app/downloads/hl7-v2-codec>, download
   `Lambogenius.Hl7Codec.LogicApps.1.1.0.nupkg`, and save it in [`packages/`](packages). Every sample's project finds
   it there through the repository's `nuget.config`.
3. **HL7's v2.5 schemas (optional, free).** The samples run without them, but some steps need a schema (see
   [Schemas](#schemas)). Sign in at [hl7.org](https://www.hl7.org) with your own free HL7 account and download the
   v2.xml schemas for HL7 v2.5. Unzip them anywhere outside this repository, for example to `C:\hl7\v2xml\2.5`
   (the folder with `segments.xsd` and `ADT_A01.xsd`).
4. **No license to run the samples.** Under Azure Functions Core Tools (`func start`, which `run.ps1` uses) the
   actions run without one and log a reminder. Anywhere else, Azure included, they need a license token in the app
   setting `LAMBOGENIUS_LICENSE`: a free [developer license](https://lambogenius.com/app/licensing?start=hl7-developer)
   for development and testing, or the [30-day trial](https://lambogenius.com/app/licensing?start=hl7-trial) or a
   paid license for production. One token covers both the HL7 v2 Codec and the HL7 MLLP Connector.

Every sample starts the same way:

```powershell
cd 01-basics
./run.ps1 -V2XmlFolder C:\hl7\v2xml\2.5   # generates the schemas, builds the project, starts the Logic App
# or, without HL7's schemas:
./run.ps1
# in a second window:
./demo.ps1                                # every step, checked; exits with 1 when a check fails
```

Instead of `-V2XmlFolder`, you can set the environment variable `HL7_V2XML_FOLDER` once.

Clone to a short path, such as `C:\src\hl7-samples`. The builds write files up to about 160 characters below the
clone folder, so a clone folder path longer than about 95 characters exceeds the Windows 260-character path limit
and the build fails.

The first build restores NuGet packages and takes a few minutes. The Logic App is ready when its log shows
`Host lock lease acquired`. **Ctrl+C** stops it and everything `run.ps1` started.

Each sample has its own port, so several can run at once:

| Sample | Logic App |
|---|---|
| 01 | 7201 |
| 02 | 7202 |
| 03 | 7203 |
| 04 | 7204 |

All samples share one Azurite on ports 10000–10002. If one is already running there, `run.ps1` uses it. If another
program holds one of those ports (VS Code sometimes holds 10001), `run.ps1` starts Azurite on free ports and points
the Logic App at them.

## Schemas

The codec takes element names, nesting, field positions and validation rules from an XSD in the Logic App's
`Artifacts/Schemas` folder. It picks the schema from the message: MSH-9 gives the message structure (`ADT_A01`), and
MSH-12 the version. The schemas these samples use are generated from HL7's v2.xml schemas, with versioned roots such
as `ADT_A01_25`, so the test messages all say `2.5` in MSH-12.

**No schema is in this repository.** HL7's schemas, and anything generated from them, are HL7's content: you use
them under your own HL7 license and must not share them. So each sample makes its own:

- `run.ps1 -V2XmlFolder <folder>` runs the [HL7 v2 Schema Generator](shared/schemagen) on your v2.xml download and
  writes the schemas the sample needs (all four use `ADT_A01`) to `Artifacts/Schemas/2.5/ADT_A01_25.xsd`. It checks
  first that the folder holds v2.5. Git ignores every `Artifacts/Schemas` folder.
- Later runs of `./run.ps1` reuse the schemas already there. Delete `Artifacts/Schemas` to run without them again.
- `demo.ps1` looks at `Artifacts/Schemas`. Steps that need a schema are reported as `skip` and do not fail the demo.

**Without a schema**, Decode answers AR ("No schema found"), unless the action sets `allowSchemaless`. Then it
decodes with generic names: fields `PID_5` (1-based, as in HL7), components `PID_5_0` (0-based), sub-components
`PID_5_0_0`, and no groups. Encode works without a schema too, as long as it doesn't validate: positions come from the
numbers in the element names. Create ACK never needs one. With a schema, the names carry descriptions
(`PID_5_PatientName`, `XPN_0_FamilyName`), fields that may repeat are always arrays in JSON, groups such as
`ADT_A01_PROCEDURE` appear, and the message is validated: a missing required segment is an AE.

The generator is MIT-licensed and free. [`shared/schemagen`](shared/schemagen) holds an unchanged copy of its
PowerShell version, pinned to one commit of the public repository
[lambogenius/hl7-schemagen-vscode](https://github.com/lambogenius/hl7-schemagen-vscode), with its license. A pinned
copy, rather than a download at run time, means the samples work offline, never run code fetched from the network,
and always produce the schemas their checks expect. For your own projects, use that repository: it has the
generator as a VS Code extension, as a .NET command line and as `Hl7SchemaGen.ps1`. See
[Generating schemas](https://docs.lambogenius.com/hl7-v2-codec/generating-schemas).

## How a sample is put together

| File | What it is |
|---|---|
| `LogicApp.csproj` | references `Microsoft.Azure.Workflows.WebJobs.Extension` 1.170.91 and `Lambogenius.Hl7Codec.LogicApps`. It also removes `extensionBundle` from the `host.json` the runtime uses, so the host loads the built-in connector from this project's packages |
| `connections.json` | the `lamboHl7Codec` connection. Every action names it, even though it has no required settings. Keep `"schemaFolder": ""` (the default, `Artifacts/Schemas`): the runtime refuses an empty `parameterValues` |
| `local.settings.sample.json` | app settings; `run.ps1` copies it to `local.settings.json` (ignored by git) on the first run |
| `Artifacts/Schemas/` | generated by `run.ps1 -V2XmlFolder`; ignored by git |
| `Artifacts/Maps/` | XSLT maps for the Transform XML action (sample 03) |
| `<workflow>/workflow.json` | the workflows. Each starts with an HTTP request trigger |
| `messages/` | test messages. `.hl7` files are ER7 with one segment per line; the codec accepts CR, LF or CRLF |

A Decode action in a workflow:

```json
"Decode_HL7": {
  "type": "ServiceProvider",
  "inputs": {
    "parameters": {
      "message": "@{triggerBody()}",
      "allowSchemaless": false,
      "outputFormat": "xml"
    },
    "serviceProviderConfiguration": {
      "connectionName": "lamboHl7Codec",
      "operationId": "decode",
      "serviceProviderId": "/serviceProviders/lamboHl7Codec"
    }
  },
  "runAfter": {}
}
```

The outputs are in `body('Decode_HL7')`: `success`, `ackCode`, `xml` (or `json`), `ack`, `batchAck`, `messages[]` and
`errors[]`. HL7 problems never fail the action: they become AE or AR in the ACK, with ERR segments. Check `success` or
`ackCode`, and return the `ack`. The operations of Encode and Create ACK are `encode` and `createAck`.

## Running in Azure

The samples run locally. To deploy one:
1. Generate its schemas, then run `dotnet publish -c Release`. The schemas go with the Logic App in
   `Artifacts/Schemas`; they stay in your own deployment, under your HL7 license.
2. Zip-deploy the publish folder to a Logic App (Standard).
3. Set the app settings from `local.settings.sample.json`, and set `LAMBOGENIUS_LICENSE` to a license token from the
   [Licensing page](https://lambogenius.com/app/licensing). Without it, the actions fail with HTTP 403 and a message
   that says why.

See [Licensing](https://docs.lambogenius.com/hl7-v2-codec/licensing).

## Receiving over MLLP

These samples receive messages over HTTP so they run anywhere. To receive them from a hospital system over MLLP (TCP),
use the HL7 MLLP Connector, which works with the codec and shares its license. Its samples:
<https://github.com/lambogenius/lambogenius-mllp-connector-samples>.

## Support

Questions and bug reports: <hello@lambogenius.com>. The HL7 v2 Codec package is not part of this repository; its
license terms are on <https://lambogenius.com/products/hl7-v2-codec>. HL7 and Health Level Seven are registered
trademarks of Health Level Seven International.

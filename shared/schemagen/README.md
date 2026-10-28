# HL7 v2 Schema Generator (pinned copy)

`run.ps1 -V2XmlFolder <folder>` uses this copy to turn HL7's v2.xml schemas into the XSDs the codec reads.

| File | What it is |
|---|---|
| `Hl7SchemaGen.ps1` | the generator for PowerShell 7.2 or later. It compiles `V2XmlSchemaConverter.cs` in memory, so nothing is built or installed |
| `V2XmlSchemaConverter.cs` | the converter |
| `LICENSE` | the generator's MIT license |

Both files are unchanged copies from the public repository
[lambogenius/hl7-schemagen-vscode](https://github.com/lambogenius/hl7-schemagen-vscode), folder `generator/`, commit
`9c3c1e9e579c527b28492bac6c4ab2746453f064`. That repository also has the generator as a VS Code extension and as a
.NET command line. Use it for your own projects; this copy is here so the samples run offline and always produce the
schemas their checks expect.

The generator holds no HL7 content. The XSDs it writes do: they are made from your v2.xml download, under your HL7
license, and are not to be shared. That is why git ignores every `Artifacts/Schemas` folder in this repository.

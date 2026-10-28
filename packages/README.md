# packages

Save the HL7 v2 Codec package here:

1. Sign in at <https://lambogenius.com/app/downloads/hl7-v2-codec>.
2. Download `Lambogenius.Hl7Codec.LogicApps.1.1.0.nupkg`. Its SHA-256 is shown next to the link.
3. Save it in this folder.

The `nuget.config` at the repository root makes this folder a package source, so every sample finds the package
here. Git ignores `.nupkg` files in this folder.

Check the file before you use it (PowerShell):

```powershell
(Get-FileHash packages/Lambogenius.Hl7Codec.LogicApps.1.1.0.nupkg -Algorithm SHA256).Hash.ToLower()
```

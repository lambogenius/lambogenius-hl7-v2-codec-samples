using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml;
using System.Xml.Linq;
using System.Xml.Schema;

namespace Lambogenius.Hl7SchemaGen;

/// <summary>Options for <see cref="V2XmlSchemaConverter.Generate"/>.</summary>
public sealed class V2XmlGenerateOptions
{
    /// <summary>Target namespace of the message root.</summary>
    public string Namespace { get; set; } = V2XmlSchemaConverter.DefaultNamespace;

    /// <summary>Add the version to the root name (<c>ADT_A01_251</c>), as in the BizTalk 2.X library. Default true.</summary>
    public bool VersionedRoot { get; set; } = true;
}

/// <summary>
/// Reads HL7's v2.xml schemas (<c>datatypes.xsd</c> ← <c>fields.xsd</c> ← <c>segments.xsd</c> ← one file per message
/// structure, namespace <c>urn:hl7-org:v2xml</c>, names such as <c>PID.5</c> and <c>XPN.1</c>) and writes one
/// self-contained XSD per message structure in the codec's form:
/// <list type="bullet">
/// <item>the root (<c>ADT_A01_251</c>) starts with <c>MSH</c> and holds the whole message, groups included;</item>
/// <item>fields <c>PID_5_PatientName</c> (1-based), components <c>XPN_0_FamilyName</c> (0-based), groups
/// <c>ADT_A01_PROCEDURE</c>, descriptive parts taken from the v2.xml <c>LongName</c>;</item>
/// <item>root in the target namespace, everything below unqualified.</item>
/// </list>
/// Primitive types become plain strings (escapes are handled by the codec), <c>varies</c> becomes a mixed wildcard
/// type, and the v2.xml extension wildcards (<c>xsd:any ##other</c>) are left out: the codec keeps undefined content
/// on its own.
/// </summary>
public sealed class V2XmlSchemaConverter
{
    public const string V2XmlNamespace = "urn:hl7-org:v2xml";
    public const string DefaultNamespace = "http://lambogenius.com/HealthCare/HL7/2X";
    private const string XsdNamespace = "http://www.w3.org/2001/XMLSchema";
    private static readonly XNamespace Xs = XsdNamespace;

    private readonly XmlSchemaSet _set;
    private readonly Dictionary<string, XmlSchemaElement> _messages;

    /// <summary>The folder holding <c>segments.xsd</c> and the message files.</summary>
    public string Folder { get; }

    /// <summary>HL7 version, e.g. <c>2.5.1</c>.</summary>
    public string Version { get; }

    /// <summary>Message structures found (global elements whose content starts with MSH), sorted.</summary>
    public IReadOnlyList<string> MessageNames => _messages.Keys.OrderBy(k => k, StringComparer.Ordinal).ToList();

    /// <summary>Wildcards (<c>xsd:any</c>) left out by the last <see cref="Generate"/> call.</summary>
    public int DroppedWildcards { get; private set; }

    private V2XmlSchemaConverter(string folder, string version, XmlSchemaSet set)
    {
        Folder = folder;
        Version = version;
        _set = set;
        _messages = new Dictionary<string, XmlSchemaElement>(StringComparer.Ordinal);
        foreach (XmlSchemaElement e in set.GlobalElements.Values)
            if (e.QualifiedName.Namespace == V2XmlNamespace && !IsAnySegment(e.QualifiedName.Name) && FirstElementName(e) == "MSH")
                _messages[e.QualifiedName.Name] = e;
    }

    /// <summary>
    /// Loads the v2.xml schemas in <paramref name="folder"/> (or in the one folder below it that contains
    /// <c>segments.xsd</c>). <paramref name="version"/> may be null when the files name it.
    /// </summary>
    public static V2XmlSchemaConverter Load(string folder, string version = null)
    {
        folder = FindSchemaFolder(Path.GetFullPath(folder));
        version ??= DetectVersion(folder)
                    ?? throw new InvalidOperationException($"Could not tell the HL7 version of '{folder}'; pass it with --version (e.g. 2.5.1).");

        var settings = new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = new XmlUrlResolver() };
        var set = new XmlSchemaSet { XmlResolver = new XmlUrlResolver() };
        var loaded = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var file in Directory.EnumerateFiles(folder, "*.xsd").OrderBy(f => f, StringComparer.OrdinalIgnoreCase))
        {
            // Shared files come in through the message files' includes; adding them again would define everything twice.
            string name = Path.GetFileName(file);
            if (IsSharedFile(name)) continue;
            using var reader = XmlReader.Create(file, settings);
            var schema = XmlSchema.Read(reader, null);
            if (schema?.TargetNamespace != V2XmlNamespace) continue;
            set.Add(schema);
            loaded.Add(file);
        }
        if (loaded.Count == 0) throw new InvalidOperationException($"No v2.xml message schemas ({V2XmlNamespace}) found in '{folder}'.");
        set.Compile();
        return new V2XmlSchemaConverter(folder, version, set);
    }

    private static bool IsSharedFile(string name) =>
        name.Equals("datatypes.xsd", StringComparison.OrdinalIgnoreCase) ||
        name.Equals("fields.xsd", StringComparison.OrdinalIgnoreCase) ||
        name.Equals("segments.xsd", StringComparison.OrdinalIgnoreCase) ||
        name.Equals("messages.xsd", StringComparison.OrdinalIgnoreCase) ||
        name.Equals("batch.xsd", StringComparison.OrdinalIgnoreCase);

    private static string FindSchemaFolder(string folder)
    {
        if (!Directory.Exists(folder)) throw new DirectoryNotFoundException($"Folder '{folder}' does not exist.");
        if (File.Exists(Path.Combine(folder, "segments.xsd"))) return folder;
        var found = Directory.EnumerateFiles(folder, "segments.xsd", SearchOption.AllDirectories).Select(Path.GetDirectoryName).ToList();
        return found.Count switch
        {
            1 => found[0],
            0 => throw new InvalidOperationException($"'{folder}' does not contain HL7 v2.xml schemas (no segments.xsd)."),
            _ => throw new InvalidOperationException($"'{folder}' contains several v2.xml schema sets; pick one:\n  " + string.Join("\n  ", found)),
        };
    }

    /// <summary>The version named in the v2.xml files' header comments ("... for version v2.5"), or null.</summary>
    public static string DetectVersion(string folder)
    {
        foreach (var name in new[] { "segments.xsd", "fields.xsd", "datatypes.xsd" })
        {
            string path = Path.Combine(folder, name);
            if (!File.Exists(path)) continue;
            using var reader = new StreamReader(path);
            var buffer = new char[4096];
            int n = reader.Read(buffer, 0, buffer.Length);
            var m = Regex.Match(new string(buffer, 0, n), @"version\s+v?(2(?:\.\d+){1,2})\b", RegexOptions.IgnoreCase);
            if (m.Success) return m.Groups[1].Value;
        }
        return null;
    }

    // ------------------------------------------------------------------ generation

    /// <summary>Root name the generated schema uses for <paramref name="message"/>: <c>ADT_A01_251</c> or <c>ADT_A01</c>.</summary>
    public string RootName(string message, V2XmlGenerateOptions options = null) =>
        (options ?? new V2XmlGenerateOptions()).VersionedRoot ? message + "_" + new string(Version.Where(char.IsDigit).ToArray()) : message;

    /// <summary>Builds the XSD for one message structure (e.g. <c>ADT_A01</c>).</summary>
    public XDocument Generate(string message, V2XmlGenerateOptions options = null)
    {
        options ??= new V2XmlGenerateOptions();
        if (!_messages.TryGetValue(message, out var root))
            throw new ArgumentException($"'{message}' is not a message structure in '{Folder}'. Available: {string.Join(", ", MessageNames)}.");

        var ctx = new Context();
        DroppedWildcards = 0;

        var rootElement = new XElement(Xs + "element", new XAttribute("name", RootName(message, options)),
            new XElement(Xs + "complexType", Particle(ContentOf(root), ctx)));

        var schema = new XElement(Xs + "schema",
            new XAttribute(XNamespace.Xmlns + "xs", XsdNamespace),
            new XAttribute("xmlns", options.Namespace),
            new XAttribute("targetNamespace", options.Namespace),
            new XAttribute("elementFormDefault", "unqualified"),
            new XComment($" {RootName(message, options)}: HL7 v{Version} message structure {message} with MSH and the body in one schema. "),
            new XComment(" Generated by Hl7SchemaGen from HL7 International's v2.xml schemas. HL7 content (c) Health Level Seven International; "
                         + "use it under your own HL7 license and do not redistribute it. "),
            rootElement);

        // Segments in the order the message first uses them, then the datatypes they need.
        foreach (var seg in ctx.SegmentOrder)
            schema.Add(SegmentType(seg, ctx));
        for (int i = 0; i < ctx.TypeOrder.Count; i++) // grows while composites pull in their component types
            ctx.TypeElements.Add(DataType(ctx.TypeOrder[i], ctx));
        foreach (var t in ctx.TypeElements.OrderBy(t => (string)t.Attribute("name"), StringComparer.Ordinal))
            schema.Add(t);

        return new XDocument(new XDeclaration("1.0", "utf-8", null), schema);
    }

    /// <summary>Writes the XSD for <paramref name="message"/> to <c>&lt;outFolder&gt;/&lt;version&gt;/&lt;root&gt;.xsd</c> and returns the path.</summary>
    public string Write(string message, string outFolder, V2XmlGenerateOptions options = null)
    {
        var doc = Generate(message, options);
        string dir = Path.Combine(outFolder, Version);
        Directory.CreateDirectory(dir);
        string path = Path.Combine(dir, RootName(message, options) + ".xsd");
        var settings = new XmlWriterSettings { Indent = true, IndentChars = "  ", Encoding = new UTF8Encoding(true) };
        using (var writer = XmlWriter.Create(path, settings))
            doc.Save(writer);
        return path;
    }

    private sealed class Context
    {
        public readonly List<XmlSchemaElement> SegmentOrder = new();
        public readonly HashSet<string> Segments = new(StringComparer.Ordinal);
        public readonly List<XmlSchemaType> TypeOrder = new();
        public readonly HashSet<string> Types = new(StringComparer.Ordinal);
        public readonly List<XElement> TypeElements = new();
    }

    // ------------------------------------------------------------------ message structure

    private XElement Particle(XmlSchemaParticle p, Context ctx)
    {
        switch (p)
        {
            case XmlSchemaGroupBase g:
            {
                var el = new XElement(Xs + (g is XmlSchemaChoice ? "choice" : "sequence"));
                AddOccurs(el, g, defaultOne: true);
                foreach (XmlSchemaObject item in g.Items)
                {
                    if (item is XmlSchemaAny) { DroppedWildcards++; continue; }
                    if (!(item is XmlSchemaParticle child)) continue;
                    var next = Particle(child, ctx);
                    if (next.Name == Xs + "any" && el.LastNode is XElement prev && prev.Name == Xs + "any")
                        MergeWildcards(prev, next); // two in a row (RTB_Knn) would be ambiguous
                    else
                        el.Add(next);
                }
                return el;
            }

            case XmlSchemaElement e:
            {
                var global = Resolve(e);
                string name = global.QualifiedName.Name;
                if (IsAnySegment(name))
                {
                    // Placeholder for any segment (the standard's "Hxx" / "Zxx"); in ER7 there is no wrapper element.
                    // ##other cannot clash with the unqualified segments around it (an ##any wildcard next to an
                    // optional segment breaks Unique Particle Attribution). The codec leaves the segment it accepts
                    // out of XSD validation, so the wildcard is optional here.
                    return new XElement(Xs + "any", new XAttribute("namespace", "##other"), new XAttribute("processContents", "skip"),
                        new XAttribute("minOccurs", 0),
                        new XAttribute("maxOccurs", e.MaxOccurs == decimal.MaxValue ? "unbounded" : ((int)e.MaxOccurs).ToString()));
                }
                if (IsSegment(global))
                {
                    if (ctx.Segments.Add(name)) ctx.SegmentOrder.Add(global);
                    var segEl = new XElement(Xs + "element", new XAttribute("name", name), new XAttribute("type", SegmentTypeName(name)));
                    AddOccurs(segEl, e);
                    return segEl;
                }

                // A group: ADT_A01.PROCEDURE -> ADT_A01_PROCEDURE, defined inline.
                var groupEl = new XElement(Xs + "element", new XAttribute("name", name.Replace('.', '_')));
                AddOccurs(groupEl, e);
                groupEl.Add(new XElement(Xs + "complexType", Particle(ContentOf(global), ctx)));
                return groupEl;
            }

            default:
                return new XElement(Xs + "sequence");
        }
    }

    /// <summary>v2.xml's placeholders for "any segment" (a choice of every segment, or a wildcard).</summary>
    private static bool IsAnySegment(string name) => name == "anyHL7Segment" || name == "anyZSegment";

    /// <summary>A segment's content is fields named <c>SEG.n</c> (or nothing).</summary>
    private static bool IsSegment(XmlSchemaElement e)
    {
        string name = e.QualifiedName.Name;
        if (name.Contains('.')) return false;
        string first = FirstElementName(e);
        return first == null ? name.Length == 3 : first.StartsWith(name + ".", StringComparison.Ordinal);
    }

    private static string SegmentTypeName(string segment) => segment + "_Segment";

    private XElement SegmentType(XmlSchemaElement segment, Context ctx)
    {
        string id = segment.QualifiedName.Name;
        var seq = new XElement(Xs + "sequence");
        foreach (var (fieldRef, occurs) in Flatten(ContentOf(segment)))
        {
            var field = Resolve(fieldRef);
            int? position = NumberAfterDot(field.QualifiedName.Name);
            if (position == null) continue;
            var type = DataTypeOf(field.ElementSchemaType);
            Use(type, ctx);
            var el = new XElement(Xs + "element",
                new XAttribute("name", Join(id, position.Value, LongNameOf(field))),
                new XAttribute("type", TypeName(type)));
            AddOccurs(el, occurs);
            seq.Add(el);
        }
        return new XElement(Xs + "complexType", new XAttribute("name", SegmentTypeName(id)), seq);
    }

    // ------------------------------------------------------------------ datatypes

    private void Use(XmlSchemaType type, Context ctx)
    {
        if (ctx.Types.Add(TypeName(type))) ctx.TypeOrder.Add(type);
    }

    private XElement DataType(XmlSchemaType type, Context ctx)
    {
        string name = TypeName(type);
        if (name == "varies")
        {
            return new XElement(Xs + "complexType", new XAttribute("name", "varies"), new XAttribute("mixed", "true"),
                new XElement(Xs + "sequence",
                    new XElement(Xs + "any", new XAttribute("processContents", "lax"), new XAttribute("minOccurs", "0"), new XAttribute("maxOccurs", "unbounded"))));
        }

        var components = Components(type).ToList();
        if (components.Count == 0)
        {
            // Primitive (ST, NM, DTM, ...) and formatted text (FT, TX): plain strings, escapes are the codec's job.
            return new XElement(Xs + "simpleType", new XAttribute("name", name),
                new XElement(Xs + "restriction", new XAttribute("base", "xs:string")));
        }

        var seq = new XElement(Xs + "sequence");
        foreach (var (component, position, occurs) in components)
        {
            var ctype = DataTypeOf(component.ElementSchemaType);
            Use(ctype, ctx);
            var el = new XElement(Xs + "element",
                new XAttribute("name", Join(name, position - 1, LongNameOf(component))),
                new XAttribute("type", TypeName(ctype)));
            AddOccurs(el, occurs);
            seq.Add(el);
        }
        return new XElement(Xs + "complexType", new XAttribute("name", name), seq);
    }

    /// <summary>Components of a composite type: elements named <c>TYPE.n</c>, with their 1-based position.</summary>
    private IEnumerable<(XmlSchemaElement, int, XmlSchemaParticle)> Components(XmlSchemaType type)
    {
        if (!(type is XmlSchemaComplexType ct)) yield break;
        string prefix = TypeName(type) + ".";
        foreach (var (r, occurs) in Flatten(ct.ContentTypeParticle))
        {
            var c = Resolve(r);
            string name = c.QualifiedName.Name;
            if (!name.StartsWith(prefix, StringComparison.Ordinal)) continue;
            int? position = NumberAfterDot(name);
            if (position > 0) yield return (c, position.Value, occurs);
        }
    }

    /// <summary>
    /// The HL7 datatype behind a field or component type: <c>PID.5.CONTENT</c> extends <c>XPN</c>, so XPN.
    /// <c>anyType</c> (and the v2.xml <c>varies</c>) is varies; a type that ends in an XSD built-in is ST.
    /// </summary>
    private XmlSchemaType DataTypeOf(XmlSchemaType type)
    {
        for (var t = type; t != null; t = t.BaseXmlSchemaType)
        {
            var qn = t.QualifiedName;
            if (qn.IsEmpty) continue;
            if (qn.Namespace == XsdNamespace)
                return qn.Name == "anyType" ? VariesType : StringType;
            if (!qn.Name.EndsWith(".CONTENT", StringComparison.Ordinal)) return t;
        }
        return StringType;
    }

    private static readonly XmlSchemaSimpleType StringType = new() { Name = "ST" };
    private static readonly XmlSchemaComplexType VariesType = new() { Name = "varies" };

    private static string TypeName(XmlSchemaType t) => string.IsNullOrEmpty(t.QualifiedName.Name) ? t.Name : t.QualifiedName.Name;

    // ------------------------------------------------------------------ helpers

    private XmlSchemaElement Resolve(XmlSchemaElement e) =>
        !e.RefName.IsEmpty && _set.GlobalElements[e.RefName] is XmlSchemaElement g ? g : e;

    private static XmlSchemaParticle ContentOf(XmlSchemaElement e) =>
        (e.ElementSchemaType as XmlSchemaComplexType)?.ContentTypeParticle;

    private static string FirstElementName(XmlSchemaElement e)
    {
        foreach (var (el, _) in Flatten(ContentOf(e)))
            return el.QualifiedName.Name;
        return null;
    }

    private static IEnumerable<(XmlSchemaElement, XmlSchemaParticle)> Flatten(XmlSchemaParticle p)
    {
        switch (p)
        {
            case XmlSchemaElement el:
                yield return (el, el);
                break;
            case XmlSchemaGroupBase g:
                foreach (XmlSchemaObject item in g.Items)
                    if (item is XmlSchemaParticle child)
                        foreach (var x in Flatten(child))
                            yield return x;
                break;
        }
    }

    /// <summary>The fixed <c>LongName</c> attribute v2.xml puts on field and component types.</summary>
    private static string LongNameOf(XmlSchemaElement e)
    {
        if (e.ElementSchemaType is XmlSchemaComplexType ct)
            foreach (XmlSchemaAttribute a in ct.AttributeUses.Values)
                if (a.QualifiedName.Name == "LongName" && !string.IsNullOrEmpty(a.FixedValue))
                    return a.FixedValue;
        return null;
    }

    /// <summary><c>PID</c> + 5 + "Patient Name" → <c>PID_5_PatientName</c>; without a usable name <c>PID_5</c>.</summary>
    public static string Join(string prefix, int number, string longName)
    {
        string suffix = PascalCase(longName);
        return suffix.Length == 0 ? $"{prefix}_{number}" : $"{prefix}_{number}_{suffix}";
    }

    /// <summary>"Driver's License Number - Patient" → <c>DriverSLicenseNumberPatient</c>, as in the BizTalk library.</summary>
    public static string PascalCase(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return string.Empty;
        var sb = new StringBuilder();
        foreach (var word in Regex.Split(text, "[^A-Za-z0-9]+"))
            if (word.Length > 0) sb.Append(char.ToUpperInvariant(word[0])).Append(word, 1, word.Length - 1);
        string s = sb.ToString();
        // An all-digit suffix would be read as the position (PID_5_2 = component 2), so leave it out.
        return s.All(char.IsDigit) ? string.Empty : s;
    }

    private static int? NumberAfterDot(string name)
    {
        int dot = name.LastIndexOf('.');
        return dot >= 0 && int.TryParse(name.AsSpan(dot + 1), out int n) ? n : null;
    }

    private static void MergeWildcards(XElement into, XElement other)
    {
        string a = (string)into.Attribute("maxOccurs"), b = (string)other.Attribute("maxOccurs");
        into.SetAttributeValue("maxOccurs", a == "unbounded" || b == "unbounded" ? "unbounded" : (int.Parse(a) + int.Parse(b)).ToString());
    }

    private static void AddOccurs(XElement el, XmlSchemaParticle p, bool defaultOne = false)
    {
        if (p.MinOccurs != 1 || !defaultOne) el.Add(new XAttribute("minOccurs", (int)p.MinOccurs));
        if (p.MaxOccurs != 1 || !defaultOne)
            el.Add(new XAttribute("maxOccurs", p.MaxOccurs == decimal.MaxValue ? "unbounded" : ((int)p.MaxOccurs).ToString()));
    }
}

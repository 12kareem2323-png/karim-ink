using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Windows.Media.Media3D;

namespace KarimEldamatyWindows;

public sealed class Sketch3DPoint
{
    [JsonRequired]
    public double X { get; set; }
    [JsonRequired]
    public double Y { get; set; }
    [JsonRequired]
    public double Z { get; set; }
    [JsonRequired]
    public double Pressure { get; set; } = 1;
    [JsonIgnore] public Point3D Point => new(X, Y, Z);
    public Sketch3DPoint() { }
    public Sketch3DPoint(double x, double y, double z, double pressure = 1) { X = x; Y = y; Z = z; Pressure = pressure; }
    public static Sketch3DPoint From(Point3D p, double pressure = 1) => new(p.X, p.Y, p.Z, pressure);
}
public sealed class Sketch3DStroke
{
    [JsonRequired]
    public Guid Id { get; set; } = Guid.NewGuid();
    [JsonRequired]
    public List<Sketch3DPoint> Points { get; set; } = [];
    [JsonRequired]
    public InkColor Color { get; set; } = InkColor.Blue;
    [JsonRequired]
    public double Width { get; set; } = 2;
}
public sealed class Sketch3DPrimitive
{
    [JsonRequired]
    public Guid Id { get; set; } = Guid.NewGuid();
    [JsonRequired]
    public string Kind { get; set; } = "Box";
    [JsonRequired]
    public Sketch3DPoint Center { get; set; } = new();
    [JsonRequired]
    public Sketch3DPoint Size { get; set; } = new(40, 40, 40);
    [JsonRequired]
    public InkColor Color { get; set; } = InkColor.Teal;
}
public sealed class Sketch3DCamera
{
    [JsonRequired]
    public double Yaw { get; set; } = .65;
    [JsonRequired]
    public double Pitch { get; set; } = .5;
    [JsonRequired]
    public double Distance { get; set; } = 360;
    [JsonRequired]
    public Sketch3DPoint Target { get; set; } = new();
}
public sealed class Sketch3DDocument
{
    [JsonRequired]
    public int Version { get; set; } = 1;
    [JsonRequired]
    public string Title { get; set; } = "3D sketch";
    [JsonRequired]
    public string Units { get; set; } = "mm";
    [JsonRequired]
    public string Plane { get; set; } = "XZ";
    [JsonRequired]
    public double PlaneOffset { get; set; }
    [JsonRequired]
    public double GridSpacing { get; set; } = 10;
    [JsonRequired]
    public List<Sketch3DStroke> Strokes { get; set; } = [];
    [JsonRequired]
    public List<Sketch3DPrimitive> Primitives { get; set; } = [];
    [JsonRequired]
    public Sketch3DCamera Camera { get; set; } = new();
}

public static class Sketch3DFile
{
    public const int MaximumBytes = 16 * 1024 * 1024;
    public const double CoordinateLimit = 10000;
    public static readonly JsonSerializerOptions Options = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, MaxDepth = 32, UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow };
    public static void Validate(Sketch3DDocument document)
    {
        void Check(bool condition, string error) { if (!condition) throw new InvalidDataException("3D sketch: " + error); }
        bool Finite(double value, double lower, double upper) => double.IsFinite(value) && value >= lower && value <= upper;
        bool Point(Sketch3DPoint? p) => p != null && Finite(p.X, -CoordinateLimit, CoordinateLimit) && Finite(p.Y, -CoordinateLimit, CoordinateLimit) && Finite(p.Z, -CoordinateLimit, CoordinateLimit) && Finite(p.Pressure, 0, 1);
        bool Color(InkColor? c) => c != null && Finite(c.R, 0, 1) && Finite(c.G, 0, 1) && Finite(c.B, 0, 1) && Finite(c.A, 0, 1);
        Check(document.Version == 1 && document.Units == "mm", "unsupported file version or units.");
        Check(document.Title != null && Encoding.UTF8.GetByteCount(document.Title) <= 1024, "title is too long.");
        Check(document.Plane is "XY" or "XZ" or "YZ" && Finite(document.PlaneOffset, -CoordinateLimit, CoordinateLimit) && Finite(document.GridSpacing, 1, 1000), "invalid drawing plane or grid.");
        var camera = document.Camera;
        Check(camera != null && Finite(camera.Yaw, -1000, 1000) && Finite(camera.Pitch, -1.5, 1.5) && Finite(camera.Distance, 20, 60000) && Point(camera.Target), "invalid camera.");
        Check(document.Strokes != null && document.Primitives != null && document.Strokes.Count <= 200 && document.Primitives.Count <= 100, "scene limit is 200 strokes and 100 shapes.");
        var ids = new HashSet<Guid>(); var points = 0;
        foreach (var stroke in document.Strokes!)
        {
            Check(stroke != null && stroke.Points != null && ids.Add(stroke.Id) && stroke.Points.Count is > 0 and <= 4096, "invalid stroke or duplicate object.");
            points += stroke!.Points!.Count;
            Check(points <= 40000 && stroke.Points.All(Point) && Color(stroke.Color) && Finite(stroke.Width, .2, 10), "invalid or oversized stroke.");
        }
        foreach (var primitive in document.Primitives!)
            Check(primitive != null && ids.Add(primitive.Id) && primitive.Kind is "Box" or "Cylinder" or "Sphere" && Point(primitive.Center) && Color(primitive.Color) && primitive.Size != null && Finite(primitive.Size.X, 1, 2000) && Finite(primitive.Size.Y, 1, 2000) && Finite(primitive.Size.Z, 1, 2000), "invalid shape dimensions, position or colour.");
    }
    public static byte[] Encode(Sketch3DDocument document)
    {
        Validate(document);
        var bytes = JsonSerializer.SerializeToUtf8Bytes(document, Options);
        if (bytes.Length > MaximumBytes) throw new InvalidDataException("The 3D sketch exceeds 16 MB.");
        return bytes;
    }
    public static Sketch3DDocument Decode(byte[] data)
    {
        if (data.Length > MaximumBytes) throw new InvalidDataException("The 3D sketch exceeds 16 MB.");
        using var parsed = JsonDocument.Parse(data, new JsonDocumentOptions { MaxDepth = 32 });
        var required = new[] { "version", "title", "units", "plane", "planeOffset", "gridSpacing", "strokes", "primitives", "camera" };
        if (parsed.RootElement.ValueKind != JsonValueKind.Object || required.Any(key => !parsed.RootElement.TryGetProperty(key, out _))) throw new InvalidDataException("This is not a complete version 1 .karim3d scene.");
        var document = JsonSerializer.Deserialize<Sketch3DDocument>(data, Options) ?? throw new InvalidDataException("Empty 3D document.");
        Validate(document); return document;
    }
    public static Sketch3DDocument Read(string path)
    {
        if (new FileInfo(path).Length > MaximumBytes) throw new InvalidDataException("The 3D sketch exceeds 16 MB.");
        return Decode(File.ReadAllBytes(path));
    }
    public static Sketch3DDocument Copy(Sketch3DDocument document) => Decode(Encode(document));
    public static void WriteAtomic(string path, byte[] bytes)
    {
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None)) { stream.Write(bytes); stream.Flush(true); }
            File.Move(temporary, path, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}

internal sealed class Sketch3DDraft
{
    private readonly string _path;
    private byte[]? _fingerprint;
    private bool _blocked;
    public Sketch3DDraft(Guid boardId, Guid? sourceId, string? directory = null)
    {
        directory ??= Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Karim Eldamaty", "3D Drafts");
        Directory.CreateDirectory(directory);
        _path = Path.Combine(directory, boardId + "-" + (sourceId?.ToString() ?? "new") + ".karim3d");
    }
    private byte[]? Read()
    {
        if (!File.Exists(_path)) return null;
        if (new FileInfo(_path).Length > Sketch3DFile.MaximumBytes) throw new InvalidDataException("The recovery draft exceeds 16 MB.");
        return File.ReadAllBytes(_path);
    }
    public Sketch3DDocument? Recover()
    {
        try { _fingerprint = Read(); return _fingerprint == null ? null : Sketch3DFile.Decode(_fingerprint); }
        catch { _blocked = true; throw; }
    }
    public void Save(Sketch3DDocument document)
    {
        if (_blocked) throw new IOException("Automatic draft saving is unavailable. The existing draft was kept untouched; use Save 3D before closing.");
        try
        {
            using var gate = new FileStream(_path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            var existing = Read();
            if (!(existing == null && _fingerprint == null) && (existing == null || _fingerprint == null || !existing.AsSpan().SequenceEqual(_fingerprint)))
                throw new IOException("Another window changed this draft. The existing draft has been preserved; use Save 3D to keep these changes.");
            var data = Sketch3DFile.Encode(document);
            Sketch3DFile.WriteAtomic(_path, data); _fingerprint = data;
        }
        catch { _blocked = true; throw; }
    }
}

using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
namespace KarimEldamatyWindows;
public static class BoardCodec
{
    public const long MaximumBytes = 256L * 1024 * 1024;
    public static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = false,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        MaxDepth = 96,
        WriteIndented = false
    };
    public static Board Read(string path)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (stream.Length > MaximumBytes) throw new InvalidDataException("Drawing exceeds the 256 MB limit. The original file was kept.");
        var board = JsonSerializer.Deserialize<Board>(stream, Options) ?? throw new InvalidDataException("Empty drawing file.");
        Validate(board); return board;
    }
    public static string Serialize(Board board) { Validate(board); var text = JsonSerializer.Serialize(board, Options); if (Encoding.UTF8.GetByteCount(text) > MaximumBytes) throw new InvalidDataException("Drawing exceeds the 256 MB limit."); return text; }
    public static byte[] SerializeBytes(Board board) => Encoding.UTF8.GetBytes(Serialize(board));
    public static Board Deserialize(string json) { if (Encoding.UTF8.GetByteCount(json) > MaximumBytes) throw new InvalidDataException("Drawing exceeds the 256 MB limit."); var b = JsonSerializer.Deserialize<Board>(json, Options) ?? throw new InvalidDataException("Empty drawing file."); Validate(b); return b; }
    public static Board Deserialize(byte[] json) { if (json.LongLength > MaximumBytes) throw new InvalidDataException("Drawing exceeds the 256 MB limit."); var b = JsonSerializer.Deserialize<Board>(json, Options) ?? throw new InvalidDataException("Empty drawing file."); Validate(b); return b; }
    internal static Board CloneHeader(Board b) => new()
    {
        Version=b.Version, Id=b.Id, Title=b.Title, Created=b.Created, Modified=b.Modified, Background=b.Background, Width=b.Width, Height=b.Height, GridSpacing=b.GridSpacing, PointsPerMM=b.PointsPerMM, ScaleDenominator=b.ScaleDenominator, Notes=b.Notes, NotionURL=b.NotionURL, WhiteboardURL=b.WhiteboardURL, Folder=b.Folder,
        Elements=[], Extra=b.Extra is null ? null : new(b.Extra)
    };
    public static Board Clone(Board b) {var copy=CloneHeader(b);copy.Elements=b.Elements.Select(Clone).ToList();return copy;}
    public static DrawingElement Clone(DrawingElement e) => new()
    {
        Id=e.Id, Kind=e.Kind, Points=e.Points.Select(p=>p.Copy()).ToList(), Color=Clone(e.Color), Width=e.Width, Pen=e.Pen, BrushSettings=e.BrushSettings is null ? null : Clone(e.BrushSettings), Text=e.Text, FontSize=e.FontSize, ImageData=e.ImageData, Sketch3D=e.Sketch3D, Dash=e.Dash, Fill=e.Fill, Rotation=e.Rotation, Locked=e.Locked, Extra=e.Extra is null ? null : new(e.Extra)
    };
    public static InkColor Clone(InkColor c) => new(c.R,c.G,c.B,c.A) {Extra=c.Extra is null ? null : new(c.Extra)};
    public static BrushSettings Clone(BrushSettings b) => new()
    {
        MinWidth=b.MinWidth, MaxWidth=b.MaxWidth, Opacity=b.Opacity, MinOpacity=b.MinOpacity, MaxOpacity=b.MaxOpacity, PressureGamma=b.PressureGamma, PressureEnabled=b.PressureEnabled, TextureScale=b.TextureScale, PencilGrade=b.PencilGrade, Extra=b.Extra is null ? null : new(b.Extra)
    };
    public static void Validate(Board b)
    {
        static bool Range(double value,double min,double max) => double.IsFinite(value) && value >= min && value <= max;
        static void Require(bool ok,string problem) { if (!ok) throw new InvalidDataException("This drawing cannot be opened or saved: " + problem); }
        Require(b.Version == 1, $"file version {b.Version} is unsupported; version 1 is required.");
        Require(b.Id != Guid.Empty, "board identifier is missing.");
        Require(Range(b.Width,1,30000) && Range(b.Height,1,30000), "canvas dimensions must be between 1 and 30,000 drawing points.");
        Require(Range(b.PointsPerMM,.01,1000000) && Range(b.ScaleDenominator,.001,1000000) && Range(b.GridSpacing,1,1000000), "drawing scale or grid spacing is invalid.");
        Require(Range(b.Created,-63113904000,252423993599.999) && Range(b.Modified,-63113904000,252423993599.999), "drawing dates are invalid.");
        Require(b.Title is not null && b.Notes is not null && b.Folder is not null && b.Background is not null && b.NotionURL is not null && b.WhiteboardURL is not null, "a drawing text field is null.");
        Require(b.Elements is not null && b.Elements.Count <= 100000, "too many or missing drawing objects.");
        var identifiers = new HashSet<Guid>(); long count = 0;
        foreach(var e in b.Elements!)
        {
            Require(e is not null && e.Id != Guid.Empty && identifiers.Add(e.Id), "object identifiers are missing or duplicated.");
            Require(e!.Kind is "stroke" or "line" or "arrow" or "rectangle" or "ellipse" or "triangle" or "arc" or "dimension" or "text" or "image" or "symbol", "an object kind is unsupported.");
            Require(e.Points is not null && (count += e.Points.Count) <= 2000000, "too many or missing pen samples.");
            Require(Range(e.Width,double.Epsilon,1000) && Range(e.FontSize,double.Epsilon,1000) && double.IsFinite(e.Rotation), "an object width, text size or rotation is invalid.");
            Require(e.Color is not null && Range(e.Color.R,0,1) && Range(e.Color.G,0,1) && Range(e.Color.B,0,1) && Range(e.Color.A,0,1), "an object colour is invalid.");
            Require(e.Text is not null && e.Pen is not null && e.Dash is not null, "an object text field is null.");
            if (e.BrushSettings is {} s)
                Require(Range(s.MinWidth,double.Epsilon,1000) && Range(s.MaxWidth,s.MinWidth,1000) && Range(s.Opacity,0,1) && Range(s.MinOpacity,0,1) && Range(s.MaxOpacity,s.MinOpacity,1) && Range(s.PressureGamma,.15,4) && Range(s.TextureScale,.1,5) && s.PencilGrade is not null && BrushSettings.PencilGrades.Contains(s.PencilGrade), "brush or pressure settings are invalid.");
            foreach(var p in e.Points!) Require(p is not null && Range(p.X,-1000000,1000000) && Range(p.Y,-1000000,1000000) && Range(p.Pressure,0,1) && double.IsFinite(p.TiltX) && double.IsFinite(p.TiltY) && (p.Velocity is null || Range(p.Velocity.Value,0,double.MaxValue)) && (p.RawPressure is null || Range(p.RawPressure.Value,0,1)) && (p.InputDeviceKey is null || Encoding.UTF8.GetByteCount(p.InputDeviceKey) <= 255), "coordinates, pressure or device information are invalid.");
            if (e.Sketch3D is not null) Require(e.Kind == "image" && e.ImageData is {Length: > 0} && e.Sketch3D.Value.ValueKind == JsonValueKind.Object, "an editable 3D scene must belong to an image object.");
        }
    }
    public static void PruneDerivedMetadata(Board board)
    {
        if(board.Extra is null)return;var referenced=new HashSet<string>();foreach(var element in board.Elements)if(element.Extra?.TryGetValue("windowsEraseSourceKey",out var source)==true&&source.ValueKind==JsonValueKind.String&&source.GetString() is {} key)referenced.Add(key);
        foreach(var key in board.Extra.Keys.Where(key=>key.StartsWith("windowsEraseSource-",StringComparison.Ordinal)&&!referenced.Contains(key)).ToArray())board.Extra.Remove(key);
    }
    public static string Filename(string title,string extension = "engboard")
    {
        var clean=string.Concat(title.Trim().Select(c=>Path.GetInvalidFileNameChars().Contains(c)||char.IsControl(c)?'-':c));
        return (string.IsNullOrWhiteSpace(clean)?"Drawing":clean[..Math.Min(120,clean.Length)])+"."+extension.TrimStart('.');
    }
}

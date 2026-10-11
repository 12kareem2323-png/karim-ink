using System.Text.Json;
using System.Text.Json.Serialization;
using System.Windows;
using System.Windows.Media;
namespace KarimEldamatyWindows;

public class InkPoint
{
    private double x,y,pressure=1,tiltX,tiltY;private double? velocity,rawPressure;private string? deviceKey;
    internal Action? SampleChanged;
    private void Set(ref double field,double value){if(field==value)return;field=value;SampleChanged?.Invoke();}
    private void Set(ref double? field,double? value){if(field==value)return;field=value;SampleChanged?.Invoke();}
    public double X { get=>x; set=>Set(ref x,value); }
    public double Y { get=>y; set=>Set(ref y,value); }
    public double Pressure { get=>pressure; set=>Set(ref pressure,value); }
    public double TiltX { get=>tiltX; set=>Set(ref tiltX,value); }
    public double TiltY { get=>tiltY; set=>Set(ref tiltY,value); }
    public double? Velocity { get=>velocity; set=>Set(ref velocity,value); }
    public double? RawPressure { get=>rawPressure; set=>Set(ref rawPressure,value); }
    public string? InputDeviceKey { get=>deviceKey; set {if(deviceKey==value)return;deviceKey=value;SampleChanged?.Invoke();} }
    [JsonExtensionData] public Dictionary<string, JsonElement>? Extra { get; set; }
    [JsonIgnore] public Point Point => new(X, Y);
    public InkPoint() { }
    public InkPoint(double x, double y, double pressure = 1) { this.x=x;this.y=y;this.pressure=pressure; }
    public InkPoint Copy() => new(X, Y, Pressure) { TiltX = TiltX, TiltY = TiltY, Velocity = Velocity, RawPressure = RawPressure, InputDeviceKey = InputDeviceKey, Extra = Extra is null ? null : new(Extra) };
}
public class InkColor
{
    public double R { get; set; } = .14;
    public double G { get; set; } = .20;
    public double B { get; set; } = .28;
    public double A { get; set; } = 1;
    [JsonExtensionData] public Dictionary<string, JsonElement>? Extra { get; set; }
    public InkColor() { }
    public InkColor(double r, double g, double b, double a = 1) { R = r; G = g; B = b; A = a; }
    [JsonIgnore] public Color Wpf => Color.FromArgb((byte)Math.Clamp(A * 255, 0, 255), (byte)Math.Clamp(R * 255, 0, 255), (byte)Math.Clamp(G * 255, 0, 255), (byte)Math.Clamp(B * 255, 0, 255));
    public SolidColorBrush Brush(double alpha = 1) { var c = Color.FromArgb((byte)Math.Clamp(A * alpha * 255, 0, 255), (byte)Math.Clamp(R * 255, 0, 255), (byte)Math.Clamp(G * 255, 0, 255), (byte)Math.Clamp(B * 255, 0, 255)); var b = new SolidColorBrush(c); b.Freeze(); return b; }
    public static InkColor Graphite => new(.14, .20, .28);
    public static InkColor Blue => new(.16, .39, .85);
    public static InkColor Teal => new(.06, .55, .49);
    public static InkColor Red => new(.83, .23, .26);
    public static InkColor Amber => new(.94, .65, .14);
    public static InkColor Violet => new(.49, .30, .75);
    public static InkColor[] Palette => [Graphite, Blue, Teal, Red, Amber, Violet];
}
public class BrushSettings
{
    public double MinWidth { get; set; } = 1;
    public double MaxWidth { get; set; } = 4;
    public double Opacity { get; set; } = 1;
    public double MinOpacity { get; set; } = .35;
    public double MaxOpacity { get; set; } = 1;
    public double PressureGamma { get; set; } = 1;
    public bool PressureEnabled { get; set; } = true;
    public double TextureScale { get; set; } = 1;
    public string PencilGrade { get; set; } = "HB";
    [JsonExtensionData] public Dictionary<string, JsonElement>? Extra { get; set; }
    public double Width(double pressure) { var p = PressureEnabled ? Math.Clamp(double.IsFinite(pressure) ? pressure : 1, 0, 1) : 1; return Math.Max(.15, MinWidth + (Math.Max(MaxWidth, MinWidth) - MinWidth) * Math.Pow(p, Math.Clamp(PressureGamma, .15, 4))); }
    public double Alpha(double pressure) { var p = PressureEnabled ? Math.Clamp(double.IsFinite(pressure) ? pressure : 1, 0, 1) : 1; return Math.Clamp(Opacity * (MinOpacity + (MaxOpacity - MinOpacity) * Math.Pow(p, Math.Clamp(PressureGamma, .15, 4))), 0, 1); }
    public static readonly string[] PencilGrades = ["2H","H","HB","2B","4B","6B"];
    public static readonly string[] PenNames = ["Technical Fineliner", "Fountain", "Pencil", "Chalk", "Marker", "Calligraphy", "Airbrush", "Liquid Ink", "Highlighter", "Dry Erase"];
    public static BrushSettings Defaults(string pen) => pen switch
    {
        "Fountain" => new() { MinWidth = .8, MaxWidth = 6, Opacity = .97, PressureGamma = .7, TextureScale = .4 },
        "Pencil" => new() { MinWidth = 1, MaxWidth = 5, Opacity = .78, PressureGamma = 1.3 },
        "Chalk" => new() { MinWidth = 4, MaxWidth = 12, Opacity = .88, PressureGamma = .9, TextureScale = 1.6 },
        "Marker" => new() { MinWidth = 6, MaxWidth = 14, Opacity = .42, PressureGamma = .7, TextureScale = .6 },
        "Calligraphy" => new() { MinWidth = 1.5, MaxWidth = 16, Opacity = .95, PressureGamma = .85, TextureScale = .5 },
        "Airbrush" => new() { MinWidth = 8, MaxWidth = 36, Opacity = .22 },
        "Liquid Ink" => new() { MinWidth = .8, MaxWidth = 8, PressureGamma = .55, TextureScale = .25 },
        "Highlighter" => new() { MinWidth = 10, MaxWidth = 24, Opacity = .27, PressureEnabled = false, TextureScale = .3 },
        "Dry Erase" => new() { MinWidth = 3, MaxWidth = 9, Opacity = .88, PressureGamma = .8, TextureScale = .9 },
        _ => new() { MinWidth = 1.2, MaxWidth = 1.2, PressureEnabled = false, TextureScale = .3 }
    };
}
public class DrawingElement
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Kind { get; set; } = "stroke";
    private List<InkPoint> points=[];
    private List<InkPoint>? trackedPoints;
    private int trackedCount;
    private long contentVersion,cachedBoundsSignature=long.MinValue;
    private Rect cachedBounds;
    private readonly Action onPointChanged;
    private BrushSettings? legacySettings;private string? legacyPen;private double legacyWidth;
    public DrawingElement(){onPointChanged=MarkGeometryChanged;}
    public List<InkPoint> Points { get=>points; set {points=value;trackedPoints=null;MarkGeometryChanged();} }
    public void MarkGeometryChanged(){contentVersion++;cachedBoundsSignature=long.MinValue;}
    private void TrackPoints(){if(points is null)return;if(ReferenceEquals(points,trackedPoints)&&trackedCount==points.Count)return;foreach(var point in points)if(point is not null)point.SampleChanged=onPointChanged;trackedPoints=points;trackedCount=points.Count;}
    [JsonIgnore] public long RenderSignature {
        get {TrackPoints();var hash=new HashCode();hash.Add(contentVersion);hash.Add(Points.Count);hash.Add(Kind);hash.Add(Pen);hash.Add(Text);hash.Add(FontSize);hash.Add(Width);hash.Add(Rotation);hash.Add(Fill);hash.Add(Dash);hash.Add(Color.R);hash.Add(Color.G);hash.Add(Color.B);hash.Add(Color.A);hash.Add(ImageData);if(Sketch3D is {} scene)hash.Add(scene.GetHashCode());if(Extra is not null)foreach(var pair in Extra){hash.Add(pair.Key);hash.Add(pair.Value.GetHashCode());}
            if(BrushSettings is {} settings){hash.Add(settings.MinWidth);hash.Add(settings.MaxWidth);hash.Add(settings.Opacity);hash.Add(settings.MinOpacity);hash.Add(settings.MaxOpacity);hash.Add(settings.PressureGamma);hash.Add(settings.PressureEnabled);hash.Add(settings.TextureScale);hash.Add(settings.PencilGrade);}return unchecked((contentVersion<<32)^(uint)hash.ToHashCode());
        }
    }
    public InkColor Color { get; set; } = InkColor.Graphite;
    public double Width { get; set; } = 3;
    public string Pen { get; set; } = "Technical Fineliner";
    public BrushSettings? BrushSettings { get; set; }
    public string Text { get; set; } = "";
    public double FontSize { get; set; } = 24;
    public byte[]? ImageData { get; set; }
    public JsonElement? Sketch3D { get; set; }
    public string Dash { get; set; } = "Solid";
    public bool Fill { get; set; }
    public double Rotation { get; set; }
    public bool Locked { get; set; }
    [JsonExtensionData] public Dictionary<string, JsonElement>? Extra { get; set; }
    [JsonIgnore] public BrushSettings EffectiveBrushSettings
    {
        get { if (BrushSettings != null) return BrushSettings; if(legacySettings is not null&&legacyPen==Pen&&legacyWidth==Width)return legacySettings;var b = KarimEldamatyWindows.BrushSettings.Defaults(Pen); b.MaxWidth = Math.Max(.2, Width * (Pen == "Highlighter" ? 4 : Pen == "Marker" ? 1.8 : 1)); b.MinWidth = b.MaxWidth * (Pen is "Technical Fineliner" or "Pen" ? 1 : .22); legacyPen=Pen;legacyWidth=Width;legacySettings=b;return b; }
    }
    [JsonIgnore] public Rect Bounds {
        get {var signature=RenderSignature;if(signature==cachedBoundsSignature)return cachedBounds;cachedBounds=CalculateBounds();cachedBoundsSignature=signature;return cachedBounds;}
    }
    private Rect CalculateBounds()
    {
        if(Points.Count==0)return Rect.Empty;var rect=new Rect(Points[0].Point,Points[0].Point);foreach(var point in Points.Skip(1))rect.Union(point.Point);
        if(Kind=="text"){var lines=Text.Split('\n');rect.Width=Math.Max(80,lines.Max(line=>line.Length)*FontSize);rect.Height=Math.Max(FontSize*1.5,lines.Length*FontSize*1.4);}
        var padding=Kind=="stroke"?Math.Max(EffectiveBrushSettings.MaxWidth*2,2):Math.Max(Width/2,2);rect.Inflate(padding,padding);if(Rotation==0)return rect;
        var matrix=new Matrix();matrix.RotateAt(Rotation,rect.X+rect.Width/2,rect.Y+rect.Height/2);var corners=new[]{rect.TopLeft,rect.TopRight,rect.BottomLeft,rect.BottomRight}.Select(matrix.Transform).ToArray();var result=new Rect(corners[0],corners[0]);foreach(var point in corners.Skip(1))result.Union(point);return result;
    }
    public void Translate(double dx, double dy) { foreach(var p in Points) { p.X += dx; p.Y += dy; } }
}
public class Board
{
    public int Version { get; set; } = 1;
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Title { get; set; } = "Untitled drawing";
    public double Created { get; set; } = SwiftDate.Now;
    public double Modified { get; set; } = SwiftDate.Now;
    public string Background { get; set; } = "Square grid";
    public double Width { get; set; } = 1800;
    public double Height { get; set; } = 1200;
    public double GridSpacing { get; set; } = 30;
    public double PointsPerMM { get; set; } = 4;
    public double ScaleDenominator { get; set; } = 1;
    public List<DrawingElement> Elements { get; set; } = [];
    public string Notes { get; set; } = "";
    [JsonPropertyName("notionURL")] public string NotionURL { get; set; } = "";
    [JsonPropertyName("whiteboardURL")] public string WhiteboardURL { get; set; } = "";
    public string Folder { get; set; } = "General";
    [JsonExtensionData] public Dictionary<string, JsonElement>? Extra { get; set; }
    public static readonly string[] BackgroundNames = ["Plain", "Lined", "Square grid", "Dot grid", "Graph paper", "Engineering sheet", "Blueprint", "Isometric", "Polar grid", "Dark board"];
    public double Millimetres(double points) => points / PointsPerMM * ScaleDenominator;
    public double DrawingPoints(double millimetres) => millimetres * PointsPerMM / ScaleDenominator;
}
public static class SwiftDate
{
    public static readonly DateTimeOffset Epoch = new(2001,1,1,0,0,0,TimeSpan.Zero);
    public static double Now => (DateTimeOffset.UtcNow - Epoch).TotalSeconds;
    public static DateTimeOffset ToDate(double seconds) => Epoch.AddSeconds(seconds);
}

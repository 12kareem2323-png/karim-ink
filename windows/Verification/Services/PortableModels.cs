using System.Text.Json;
// Minimal portable model/geometry doubles permit testing production HTTP and export code on macOS.
// They do not exercise WPF rendering, Windows DPAPI or native Windows OCR.
namespace System.Windows
{
    public readonly record struct Point(double X,double Y);
    public struct Rect
    {
        public double X,Y,Width,Height;
        public Rect(Point a,Point b){X=Math.Min(a.X,b.X);Y=Math.Min(a.Y,b.Y);Width=Math.Abs(b.X-a.X);Height=Math.Abs(b.Y-a.Y);}
    }
}
namespace KarimEldamatyWindows
{
    public static class App { public static string? TestDataDirectory { get; set; } }
    public class InkPoint(double x=0,double y=0,double pressure=1){public double X{get;set;}=x;public double Y{get;set;}=y;public double Pressure{get;set;}=pressure;}
    public class InkColor{public double R{get;set;}=.14;public double G{get;set;}=.20;public double B{get;set;}=.28;public double A{get;set;}=1;}
    public class BrushSettings{public double MaxWidth{get;set;}=4;public double Opacity{get;set;}=1;}
    public class DrawingElement
    {
        public Guid Id{get;set;}=Guid.NewGuid();public string Kind{get;set;}="stroke";public List<InkPoint> Points{get;set;}=[];public InkColor Color{get;set;}=new();public double Width{get;set;}=3;public string Text{get;set;}="";public double FontSize{get;set;}=24;public string Dash{get;set;}="Solid";public string Pen{get;set;}="Technical Fineliner";public bool Fill{get;set;}public double Rotation{get;set;}public bool Locked{get;set;}
        public BrushSettings EffectiveBrushSettings=>new(){MaxWidth=Width};
        public System.Windows.Rect Bounds{get {var points=Points.ToArray();return new(new(points.Min(x=>x.X)-3,points.Min(x=>x.Y)-3),new(points.Max(x=>x.X)+3,points.Max(x=>x.Y)+3));}}
        public void Translate(double dx,double dy){foreach(var p in Points){p.X+=dx;p.Y+=dy;}}
    }
    public class Board
    {
        public Guid Id{get;set;}=Guid.NewGuid();public string Title{get;set;}="Test";public List<DrawingElement> Elements{get;set;}=[];public double Width{get;set;}=1800;public double Height{get;set;}=1200;public double PointsPerMM{get;set;}=4;public double ScaleDenominator{get;set;}=1;public string Background{get;set;}="Plain";public double Created{get;set;}=1;public double Modified{get;set;}=2;
        public double Millimetres(double points)=>points/PointsPerMM*ScaleDenominator;
    }
    public static class SwiftDate{public static DateTimeOffset ToDate(double seconds)=>new DateTimeOffset(2001,1,1,0,0,0,TimeSpan.Zero).AddSeconds(seconds);}
    public static class BoardCodec{public static void Validate(Board board){if(board.Elements.Select(x=>x.Id).Distinct().Count()!=board.Elements.Count)throw new InvalidDataException();}public static DrawingElement Clone(DrawingElement e)=>JsonSerializer.Deserialize<DrawingElement>(JsonSerializer.Serialize(e))!;}
    internal static class IntegrationRasterAssets { public static byte[] RenderElement(Board board,DrawingElement element,System.Windows.Rect bounds)=>BoardExport.RenderPNG(board); }
    public static class BoardExport{public static byte[] RenderPNG(Board board)=>Convert.FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5M8AAAAASUVORK5CYII=");}
}

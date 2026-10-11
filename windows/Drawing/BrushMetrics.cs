using System.Windows;
namespace KarimEldamatyWindows;
public static class BrushMetrics
{
    public static double Width(DrawingElement e,InkPoint p,Vector tangent = default)
    {
        var s = e.EffectiveBrushSettings; if(e.Pen is "Technical Fineliner" or "Pen")return Math.Max(.15,s.MaxWidth);
        var w = s.Width(p.Pressure); var speed = Math.Max(0,p.Velocity ?? 0);
        w *= e.Pen switch { "Pencil" => 1+Math.Min(1,Math.Sqrt(p.TiltX*p.TiltX+p.TiltY*p.TiltY))*1.7, "Calligraphy" when tangent.Length > .001 => .18+.82*Math.Abs((tangent.X-tangent.Y)/(tangent.Length*Math.Sqrt(2))), "Fountain" => Math.Max(.45,1-speed/2400), "Liquid Ink"=>Math.Max(.6,1-speed/3000), _=>1 };
        return Math.Max(.15,w);
    }
    public static double Opacity(DrawingElement e,InkPoint p) => e.Pen is "Technical Fineliner" or "Pen" ? e.EffectiveBrushSettings.Opacity * e.EffectiveBrushSettings.MaxOpacity : e.EffectiveBrushSettings.Alpha(p.Pressure);
}

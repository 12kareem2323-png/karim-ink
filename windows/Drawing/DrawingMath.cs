using System.Windows;
namespace KarimEldamatyWindows;
public sealed class AdaptiveInkFilter
{
    private Point? raw,filtered;private Vector velocity;private double? timestamp;
    public void Reset(){raw=null;filtered=null;timestamp=null;velocity=default;}
    public Point Sample(Point point,double time,double smoothing,double zoom)
    {
        var amount=Math.Clamp(smoothing,0,.85);if(amount==0||raw is null||filtered is null||timestamp is null||time<=timestamp||time-timestamp>=.25){raw=filtered=point;timestamp=time;velocity=default;return point;}
        var dt=Math.Max(.0001,time-timestamp.Value);var derivativeGain=Gain(3,dt);velocity+=(point-raw.Value-velocity*dt)*(derivativeGain/dt);var speed=velocity.Length*Math.Max(.05,zoom);var cutoff=2+(1-amount)*16+Math.Min(80,speed*amount*.055);var result=filtered.Value+(point-filtered.Value)*Gain(cutoff,dt);raw=point;filtered=result;timestamp=time;return result;
    }
    private static double Gain(double cutoff,double dt)=>dt/(dt+1/(2*Math.PI*cutoff));
}
public static class DrawingMath
{
    public static double CalibratedPressure(double raw,double activation) {var threshold=Math.Clamp(activation,0,.95);return Math.Clamp((Math.Clamp(raw,0,1)-threshold)/(1-threshold),0,1);}
    public static InkPoint? FixedEndpoint(InkPoint start,InkPoint end,double lengthMM,double pointsPerMM,double scaleDenominator)
    {
        if(!double.IsFinite(lengthMM)||lengthMM<=0||lengthMM>1000000||!double.IsFinite(pointsPerMM)||pointsPerMM<=0||!double.IsFinite(scaleDenominator)||scaleDenominator<=0)return null;
        var vector=end.Point-start.Point;var modelLength=lengthMM*pointsPerMM/scaleDenominator;if(vector.Length<=0||!double.IsFinite(modelLength))return null;vector.Normalize();var point=start.Point+vector*modelLength;if(!double.IsFinite(point.X)||!double.IsFinite(point.Y)||Math.Abs(point.X)>1000000||Math.Abs(point.Y)>1000000)return null;var result=end.Copy();result.X=point.X;result.Y=point.Y;return result;
    }
    public static double Distance(Point p,Point a,Point b){var v=b-a;if(v.LengthSquared<.000001)return(p-a).Length;var t=Math.Clamp(Vector.Multiply(p-a,v)/v.LengthSquared,0,1);return(p-(a+v*t)).Length;}
    public static Point Rotate(Point p,Point center,double degrees){var a=degrees*Math.PI/180;var v=p-center;return new(center.X+v.X*Math.Cos(a)-v.Y*Math.Sin(a),center.Y+v.X*Math.Sin(a)+v.Y*Math.Cos(a));}
    public static bool Hit(DrawingElement e,Point point,double tolerance)
    {
        var bounds=e.Bounds;if(bounds.IsEmpty)return false;var broad=bounds;broad.Inflate(tolerance,tolerance);if(!broad.Contains(point))return false;if(e.Rotation!=0)point=Rotate(point,new(bounds.X+bounds.Width/2,bounds.Y+bounds.Height/2),-e.Rotation);if(e.Points.Count==0)return false;
        var first=e.Points[0].Point;var last=e.Points[^1].Point;var t=tolerance+e.Width/2;var r=new Rect(first,last);
        switch(e.Kind){case "text":case "image":case "symbol":return broad.Contains(point);case "stroke":if(e.Points.Count==1)return(point-first).Length<=t+e.EffectiveBrushSettings.MaxWidth;for(int i=1;i<e.Points.Count;i++)if(Distance(point,e.Points[i-1].Point,e.Points[i].Point)<=t+e.EffectiveBrushSettings.MaxWidth/2)return true;return false;case "line":case "arrow":case "dimension":return Distance(point,first,last)<=t;case "rectangle":if(e.Fill&&r.Contains(point))return true;return Edges(r).Any(x=>Distance(point,x.Item1,x.Item2)<=t);case "ellipse":if(r.Width<.01||r.Height<.01)return Distance(point,first,last)<=t;var normalized=Math.Sqrt(Math.Pow((point.X-r.X-r.Width/2)/(r.Width/2),2)+Math.Pow((point.Y-r.Y-r.Height/2)/(r.Height/2),2));return e.Fill?normalized<=1+t/Math.Max(1,Math.Min(r.Width,r.Height)/2):Math.Abs(normalized-1)*Math.Min(r.Width,r.Height)/2<=t;case "triangle":var pts=e.Points.Count>=3?e.Points.Take(3).Select(p=>p.Point).ToArray():[new Point(r.X+r.Width/2,r.Top),r.BottomRight,r.BottomLeft];return Enumerable.Range(0,3).Any(i=>Distance(point,pts[i],pts[(i+1)%3])<=t)||(e.Fill&&InPolygon(point,pts));case "arc":if(r.Width<.01||r.Height<.01)return false;var arcPts=Enumerable.Range(0,41).Select(i=>new Point(r.X+r.Width/2+Math.Cos(Math.PI+i*Math.PI/40)*r.Width/2,r.Bottom+Math.Sin(Math.PI+i*Math.PI/40)*r.Height)).ToArray();return Enumerable.Range(1,40).Any(i=>Distance(point,arcPts[i-1],arcPts[i])<=t);default:return false;}
    }
    public static bool InPolygon(Point p,IReadOnlyList<Point> poly){var inside=false;for(int i=0,j=poly.Count-1;i<poly.Count;j=i++){var a=poly[i];var b=poly[j];if((a.Y>p.Y)!=(b.Y>p.Y)&&p.X<(b.X-a.X)*(p.Y-a.Y)/(b.Y-a.Y)+a.X)inside=!inside;}return inside;}
    public static IEnumerable<(Point,Point)> Edges(Rect r){yield return(r.TopLeft,r.TopRight);yield return(r.TopRight,r.BottomRight);yield return(r.BottomRight,r.BottomLeft);yield return(r.BottomLeft,r.TopLeft);}
    public static Point[] Corners(Rect r)=>[r.TopLeft,r.TopRight,r.BottomRight,r.BottomLeft];
    public static DrawingElement CorrectShape(DrawingElement original, double zoom,
        InkShapeMode mode = InkShapeMode.Hold, IReadOnlyList<Point>? input = null)
    {
        if (original.Pen is "Highlighter" or "Airbrush" || mode == InkShapeMode.Off)
            return original;
        var fit = InkShapeRecognizer.Detect(input ?? original.Points.Select(p => p.Point).ToArray(), zoom, mode);
        if (fit is null) return original;

        var result = BoardCodec.Clone(original);
        result.Kind = fit.Kind;
        result.Rotation = fit.Rotation;
        result.Points = fit.Kind == "line"
            ? [original.Points[0].Copy(), original.Points[^1].Copy()]
            : fit.Vertices.Select(point => new InkPoint(point.X, point.Y)).ToList();
        if (fit.Kind == "line")
        {
            result.Points[0].X = fit.Vertices[0].X;
            result.Points[0].Y = fit.Vertices[0].Y;
            result.Points[1].X = fit.Vertices[1].X;
            result.Points[1].Y = fit.Vertices[1].Y;
        }
        return result;
    }
}

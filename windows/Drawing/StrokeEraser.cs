using System.Text.Json;
using System.Windows;
namespace KarimEldamatyWindows;

/// Removes centreline intervals intersecting the eraser plus the pressure-dependent stroke radius.
/// Unchanged samples keep pressure, tilt, raw pressure, velocity, device and extension metadata.
public static class StrokeEraser
{
    public static double PressureRadius(double radius,double? deliveredPressure,double zoom) => Math.Max(2/Math.Max(.02,zoom),Math.Clamp(radius,1,1000)*(.35+.65*Math.Clamp(deliveredPressure??1,0,1)));
    public static IReadOnlyList<DrawingElement> Split(DrawingElement source,Point center,double radius)
    {
        if(source.Kind!="stroke"||source.Locked||source.Points.Count==0||!double.IsFinite(radius)||radius<=0)return[source];
        var bounds=source.Bounds;bounds.Inflate(radius,radius);if(!bounds.Contains(center))return[source];
        var rotationCenter=new Point(source.Bounds.X+source.Bounds.Width/2,source.Bounds.Y+source.Bounds.Height/2);
        var points=source.Points.Select(p=>{var c=p.Copy();if(source.Rotation!=0){var position=DrawingMath.Rotate(p.Point,rotationCenter,source.Rotation);c.X=position.X;c.Y=position.Y;}return c;}).ToList();
        if(points.Count==1)return(points[0].Point-center).Length<=radius+BrushMetrics.Width(source,points[0])/2?[]:[source];
        var parts=new List<List<InkPoint>>();var current=new List<InkPoint>();var changed=false;
        void Flush(){if(current.Count>0){parts.Add(current);current=[];}}
        void Add(InkPoint p){if(current.Count==0||(current[^1].Point-p.Point).Length>.0000001)current.Add(p.Copy());}
        for(int i=1;i<points.Count;i++) {
            var a=points[i-1];var b=points[i];var vector=b.Point-a.Point;var r=radius+Math.Max(BrushMetrics.Width(source,a,vector),BrushMetrics.Width(source,b,vector))/2;var offset=a.Point-center;var aa=vector.LengthSquared;
            if(aa<1e-12){if(offset.Length<=r){changed=true;Flush();}else{Add(a);Add(b);}continue;}
            var bb=2*Vector.Multiply(offset,vector);var cc=offset.LengthSquared-r*r;var discriminant=bb*bb-4*aa*cc;
            if(discriminant<=0){Add(a);Add(b);continue;}
            var root=Math.Sqrt(discriminant);var enter=(-bb-root)/(2*aa);var leave=(-bb+root)/(2*aa);var low=Math.Max(0,enter);var high=Math.Min(1,leave);
            if(low>=high||leave<=0||enter>=1){Add(a);Add(b);continue;}
            changed=true;
            if(low>1e-10){Add(a);Add(Interpolate(a,b,low));}Flush();
            if(high<1-1e-10){Add(Interpolate(a,b,high));Add(b);}
        }
        Flush();if(!changed)return[source];
        var result=new List<DrawingElement>();foreach(var pointsPart in parts){var element=new DrawingElement{Id=result.Count==0?source.Id:Guid.NewGuid(),Kind=source.Kind,Points=pointsPart,Color=BoardCodec.Clone(source.Color),Width=source.Width,Pen=source.Pen,BrushSettings=source.BrushSettings is null?null:BoardCodec.Clone(source.BrushSettings),Text=source.Text,FontSize=source.FontSize,ImageData=source.ImageData,Sketch3D=source.Sketch3D,Dash=source.Dash,Fill=source.Fill,Rotation=0,Locked=source.Locked,Extra=source.Extra is null?null:new(source.Extra)};result.Add(element);}return result;
    }
    private static InkPoint Interpolate(InkPoint a,InkPoint b,double t)
    {
        if(t<=1e-10)return a.Copy();if(t>=1-1e-10)return b.Copy();
        var p=new InkPoint(a.X+(b.X-a.X)*t,a.Y+(b.Y-a.Y)*t,a.Pressure+(b.Pressure-a.Pressure)*t){TiltX=a.TiltX+(b.TiltX-a.TiltX)*t,TiltY=a.TiltY+(b.TiltY-a.TiltY)*t,Velocity=a.Velocity is {} av&&b.Velocity is {} bv?av+(bv-av)*t:null,RawPressure=null,InputDeviceKey=a.InputDeviceKey==b.InputDeviceKey?a.InputDeviceKey:null,Extra=new(){["windowsInterpolatedEraseBoundary"]=JsonSerializer.SerializeToElement(true)}};
        return p;
    }
}

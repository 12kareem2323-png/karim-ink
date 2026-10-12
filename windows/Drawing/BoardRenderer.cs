using System.Globalization;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
namespace KarimEldamatyWindows;

public static class BoardRenderer
{
    private static readonly ConditionalWeakTable<byte[],WeakReference<BitmapSource>> images = new();
    private static readonly Dictionary<string,BitmapSource> formulas = [];
    private static readonly Dictionary<string,BitmapSource> symbols = [];
    public static IEnumerable<DrawingElement> DrawingOrder(IEnumerable<DrawingElement> elements) => elements.Where(e=>e.Pen=="Highlighter").Concat(elements.Where(e=>e.Pen!="Highlighter"));
    public static Rect ElementBounds(DrawingElement e) => e.Bounds;
    public static InkColor VisibleColor(InkColor c,Board board) => board.Background is "Blueprint" or "Dark board" && Math.Abs(c.R-.14)<.001 && Math.Abs(c.G-.20)<.001 && Math.Abs(c.B-.28)<.001 ? new(.91,.96,1,c.A) : c;
    public static DrawingGroup BuildDrawing(Board board)
    {
        BoardCodec.Validate(board); var group = new DrawingGroup(); using(var dc=group.Open()) {dc.PushClip(new RectangleGeometry(new Rect(0,0,board.Width,board.Height))); DrawBackground(dc,board,new(0,0,board.Width,board.Height),1);foreach(var e in DrawingOrder(board.Elements))DrawElement(dc,e,board);dc.Pop();} group.Freeze();return group;
    }
    public static DrawingGroup BuildElement(DrawingElement element,Board board) {var g = new DrawingGroup();using(var dc=g.Open())DrawElement(dc,element,board);g.Freeze();return g;}
    public static void DrawBackground(DrawingContext dc,Board b,Rect visible,double zoom)
    {
        var paper = b.Background == "Blueprint" ? new InkColor(.075,.20,.36) : b.Background == "Dark board" ? new(.10,.12,.15) : new(.998,.994,.98);
        dc.DrawRectangle(paper.Brush(),null,visible); if(b.Background is "Plain" or "Dark board")return;
        var spacing = Math.Clamp(b.GridSpacing,8,200);while(spacing*zoom<8)spacing*=5;
        var dark = b.Background == "Blueprint"; var thin = dark ? new InkColor(1,1,1,.13) : new(.41,.57,.67,.17);var strong = dark ? new InkColor(1,1,1,.27) : new(.30,.46,.58,.26);
        var pen = new Pen(thin.Brush(),.65/zoom);pen.Freeze();var major = new Pen(strong.Brush(),1/zoom);major.Freeze();
        dc.PushClip(new RectangleGeometry(visible));
        void Grid(double step,Pen p,bool vertical=true) {for(var y=Math.Floor(visible.Top/step)*step;y<=visible.Bottom;y+=step)dc.DrawLine(p,new(visible.Left,y),new(visible.Right,y));if(vertical)for(var x=Math.Floor(visible.Left/step)*step;x<=visible.Right;x+=step)dc.DrawLine(p,new(x,visible.Top),new(x,visible.Bottom));}
        switch(b.Background) {
            case "Lined": Grid(spacing,pen,false);dc.DrawLine(new Pen(new InkColor(.83,.23,.26,.23).Brush(),.8/zoom),new(80,visible.Top),new(80,visible.Bottom));break;
            case "Dot grid": {
                var tile = new DrawingGroup();using(var t=tile.Open())t.DrawEllipse(strong.Brush(),null,new(spacing/2,spacing/2),1/zoom,1/zoom);tile.Freeze();var brush=new DrawingBrush(tile){TileMode=TileMode.Tile,ViewportUnits=BrushMappingMode.Absolute,Viewport=new(0,0,spacing,spacing),ViewboxUnits=BrushMappingMode.Absolute,Viewbox=new(0,0,spacing,spacing)};brush.Freeze();dc.DrawRectangle(brush,null,visible);break;
            }
            case "Isometric": {
                var row=spacing*Math.Sqrt(3)/2;Grid(row,pen,false);
                foreach(var slope in new[]{-Math.Sqrt(3),Math.Sqrt(3)}) {var intercepts = new[]{visible.TopLeft,visible.TopRight,visible.BottomLeft,visible.BottomRight}.Select(p=>p.Y-slope*p.X).ToArray();for(var c=Math.Floor(intercepts.Min()/row)*row;c<=intercepts.Max();c+=row)dc.DrawLine(pen,new(visible.Left,slope*visible.Left+c),new(visible.Right,slope*visible.Right+c));}break;
            }
            case "Polar grid": {var center=new Point(b.Width/2,b.Height/2);var radius=DrawingMath.Corners(visible).Max(p=>(p-center).Length);var nearestX=Math.Max(Math.Max(visible.Left-center.X,center.X-visible.Right),0);var nearestY=Math.Max(Math.Max(visible.Top-center.Y,center.Y-visible.Bottom),0);var minimum=Math.Sqrt(nearestX*nearestX+nearestY*nearestY);for(var r=Math.Max(spacing,Math.Floor(minimum/spacing)*spacing);r<=radius;r+=spacing)dc.DrawEllipse(null,pen,center,r,r);for(var d=0;d<360;d+=15){var a=d*Math.PI/180;dc.DrawLine(pen,center,new(center.X+Math.Cos(a)*radius,center.Y+Math.Sin(a)*radius));}break;}
            default: var fine = b.Background == "Graph paper" && spacing/5*zoom>=4 ? spacing/5 : spacing;Grid(fine,pen);if(b.Background is "Graph paper" or "Engineering sheet" or "Blueprint")Grid(b.Background == "Graph paper" ? spacing : spacing*5,major);break;
        }
        if(b.Background == "Engineering sheet" && b.Width>100 && b.Height>170){var border=new Rect(36,36,b.Width-72,b.Height-72);var box=new Rect(Math.Max(border.Left,border.Right-620),border.Bottom-98,Math.Min(620,border.Width),98);dc.DrawRectangle(null,new Pen(new InkColor(.29,.38,.45,.72).Brush(),1.3),border);dc.DrawRectangle(paper.Brush(.90),major,box);dc.DrawLine(major,new(box.Left,box.Top+52),new(box.Right,box.Top+52));DrawText(dc,b.Title,new(box.Left+14,box.Top+10),21,InkColor.Graphite);DrawText(dc,$"DRAWING SCALE  1:{Formatted(b.ScaleDenominator)}",new(box.Left+14,box.Top+63),14,InkColor.Graphite);DrawText(dc,"DIMENSIONS IN mm",new(box.Left+box.Width*.58,box.Top+63),14,InkColor.Graphite);}
        dc.Pop();
    }
    public static void DrawElement(DrawingContext dc,DrawingElement e,Board board)
    {
        if(e.Points.Count==0)return;var first=e.Points[0].Point;var last=e.Points[^1].Point;var rect=new Rect(first,last);var color=VisibleColor(e.Color,board);var pen=MakePen(color,e.Width,e.Dash);var fill=e.Fill?color.Brush(.15):null;
        if(e.Rotation != 0){var bounds=e.Bounds;dc.PushTransform(new RotateTransform(e.Rotation,bounds.X+bounds.Width/2,bounds.Y+bounds.Height/2));}
        switch(e.Kind){
            case "stroke":DrawStroke(dc,e,color);break;
            case "line":dc.DrawLine(pen,first,last);break;
            case "arrow":dc.DrawLine(pen,first,last);ArrowHead(dc,last,first,Math.Max(12,e.Width*4),pen);break;
            case "rectangle":dc.DrawRectangle(fill,pen,rect);break;
            case "ellipse":dc.DrawEllipse(fill,pen,new(rect.X+rect.Width/2,rect.Y+rect.Height/2),rect.Width/2,rect.Height/2);break;
            case "triangle": {var points=e.Points.Count>=3?e.Points.Take(3).Select(p=>p.Point).ToArray():[new Point(rect.X+rect.Width/2,rect.Top),rect.BottomRight,rect.BottomLeft];dc.DrawGeometry(fill,pen,Polygon(points));break;}
            case "arc": {var path=new StreamGeometry();using(var g=path.Open()){g.BeginFigure(rect.BottomLeft,false,false);g.ArcTo(rect.BottomRight,new Size(rect.Width/2,rect.Height),0,false,SweepDirection.Clockwise,true,false);}path.Freeze();dc.DrawGeometry(null,pen,path);break;}
            case "dimension": {dc.DrawLine(pen,first,last);ArrowHead(dc,first,last,Math.Max(10,e.Width*3),pen);ArrowHead(dc,last,first,Math.Max(10,e.Width*3),pen);var v=last-first;if(v.Length>.01){v.Normalize();var n=new Vector(-v.Y,v.X)*12;dc.DrawLine(pen,first-n,first+n);dc.DrawLine(pen,last-n,last+n);}var label=string.IsNullOrWhiteSpace(e.Text)?$"{Formatted(board.Millimetres((last-first).Length))} mm":e.Text;DrawText(dc,label,new((first.X+last.X)/2,(first.Y+last.Y)/2-e.FontSize-5),e.FontSize,color,center:true);break;}
            case "text":DrawText(dc,e.Text,first,e.FontSize,color);break;
            case "image": if(e.ImageData is {Length:>0})try{dc.DrawImage(DecodeImage(e.ImageData),rect);}catch(Exception ex) when(ex is IOException or NotSupportedException or ArgumentException){DrawText(dc,"Image unavailable",rect.TopLeft,16,color);}break;
            case "symbol": {
                if(e.Text.StartsWith("mathlatex:",StringComparison.Ordinal)){var key=e.Text+"|"+e.FontSize.ToString(CultureInfo.InvariantCulture)+"|"+color.R.ToString(CultureInfo.InvariantCulture)+"|"+color.G.ToString(CultureInfo.InvariantCulture)+"|"+color.B.ToString(CultureInfo.InvariantCulture)+"|"+color.A.ToString(CultureInfo.InvariantCulture);
                    if(!formulas.TryGetValue(key,out var formula)){formula=DecodeImage(FormulaRenderer.RenderPng(e.Text[10..],color,e.FontSize));if(formulas.Count>=64)formulas.Remove(formulas.Keys.First());formulas[key]=formula;}dc.DrawImage(formula,rect);break;}
                var id=e.Text.StartsWith("catalog:",StringComparison.Ordinal)?e.Text[8..]:e.Text;var file=Path.Combine(AppContext.BaseDirectory,"Resources","Symbols",id+".png");if(id.IndexOfAny(Path.GetInvalidFileNameChars())<0&&File.Exists(file)){if(!symbols.TryGetValue(id,out var image)){image=DecodeImage(File.ReadAllBytes(file));if(symbols.Count>=128)symbols.Remove(symbols.Keys.First());symbols[id]=image;}var mask=new ImageBrush(image){Stretch=Stretch.Fill,ViewportUnits=BrushMappingMode.Absolute,Viewport=rect};mask.Freeze();dc.PushOpacityMask(mask);dc.DrawRectangle(color.Brush(),null,rect);dc.Pop();}else DrawLegacySymbol(dc,id,rect,pen);break;
            }
        }
        if(e.Rotation!=0)dc.Pop();
    }
    public static Pen MakePen(InkColor color,double width,string dash="Solid")
    {
        var p=new Pen(color.Brush(),Math.Max(.15,width)){StartLineCap=PenLineCap.Round,EndLineCap=PenLineCap.Round,LineJoin=PenLineJoin.Round};p.DashStyle=dash switch{"Dashed" or "Hidden"=>new([4+6/width,2+4/width],0),"Centre"=>new([20/width,5/width,3/width,5/width],0),"Dotted"=>new([1/width,2+3/width],0),_=>DashStyles.Solid};p.Freeze();return p;
    }
    public static BitmapSource DecodeImage(byte[] data)
    {
        if(images.TryGetValue(data,out var cached)&&cached.TryGetTarget(out var retained))return retained;using(var stream=new MemoryStream(data,false)){var metadata=BitmapDecoder.Create(stream,BitmapCreateOptions.DelayCreation,BitmapCacheOption.None);var frame=metadata.Frames[0];var longest=Math.Max(frame.PixelWidth,frame.PixelHeight);stream.Position=0;var image=new BitmapImage();image.BeginInit();image.CacheOption=BitmapCacheOption.OnLoad;if(longest>4096){if(frame.PixelWidth>=frame.PixelHeight)image.DecodePixelWidth=4096;else image.DecodePixelHeight=4096;}image.StreamSource=stream;image.EndInit();image.Freeze();images.Remove(data);images.Add(data,new(image));return image;}
    }
    public static void DrawText(DrawingContext dc,string text,Point point,double size,InkColor color,bool center=false)
    {
        var rtl=text.Any(c=>c is >= '\u0590' and <= '\u08FF');var ft=new FormattedText(text,CultureInfo.CurrentCulture,rtl?FlowDirection.RightToLeft:FlowDirection.LeftToRight,new Typeface("Segoe UI"),Math.Clamp(size,.1,1000),color.Brush(),1){MaxTextWidth=30000,MaxTextHeight=30000,TextAlignment=TextAlignment.Left};ft.MaxTextWidth=Math.Clamp(ft.WidthIncludingTrailingWhitespace+1,1,30000);if(center)point.X-=ft.Width/2;dc.DrawText(ft,point);
    }
    public static string Formatted(double n) => n.ToString("0.###",CultureInfo.InvariantCulture);
    private static StreamGeometry Polygon(IReadOnlyList<Point> points){var g=new StreamGeometry();using(var c=g.Open()){c.BeginFigure(points[0],true,true);c.PolyLineTo(points.Skip(1).ToArray(),true,true);}g.Freeze();return g;}
    private static void ArrowHead(DrawingContext dc,Point tip,Point toward,double size,Pen pen){var v=toward-tip;if(v.Length<.001)return;v.Normalize();var n=new Vector(-v.Y,v.X);dc.DrawLine(pen,tip,tip+v*size+n*(size*.42));dc.DrawLine(pen,tip,tip+v*size-n*(size*.42));}
    private static void DrawLegacySymbol(DrawingContext dc,string name,Rect r,Pen p){if(name.Contains("resistor")){var points=new List<Point>{new(r.Left,r.Y+r.Height/2)};for(int i=1;i<10;i++)points.Add(new(r.Left+r.Width*i/10,r.Top+r.Height*(i%2==0?.75:.25)));points.Add(new(r.Right,r.Y+r.Height/2));var g=new StreamGeometry();using(var c=g.Open()){c.BeginFigure(points[0],false,false);c.PolyLineTo(points.Skip(1).ToArray(),true,true);}g.Freeze();dc.DrawGeometry(null,p,g);}else if(name.Contains("capacitor")){dc.DrawLine(p,new(r.Left,r.Y+r.Height/2),new(r.Left+r.Width*.45,r.Y+r.Height/2));dc.DrawLine(p,new(r.Left+r.Width*.45,r.Top),new(r.Left+r.Width*.45,r.Bottom));dc.DrawLine(p,new(r.Left+r.Width*.55,r.Top),new(r.Left+r.Width*.55,r.Bottom));dc.DrawLine(p,new(r.Left+r.Width*.55,r.Y+r.Height/2),new(r.Right,r.Y+r.Height/2));}else {dc.DrawRectangle(null,p,r);DrawText(dc,name,r.TopLeft,14,InkColor.Graphite);}}
    public static void DrawStroke(DrawingContext dc,DrawingElement e,InkColor color)
    {
        if(e.Points.Count==0)return;var mean=e.Points.Average(p=>p.Pressure);var alpha=BrushMetrics.Opacity(e,new(0,0,mean));var settings=e.EffectiveBrushSettings;
        if(e.Pen is "Technical Fineliner" or "Pen"){
            var path=new StreamGeometry();using(var drawing=path.Open()){drawing.BeginFigure(e.Points[0].Point,false,false);drawing.PolyLineTo(e.Points.Skip(1).Select(point=>point.Point).ToArray(),true,true);}path.Freeze();var pen=new Pen(color.Brush(alpha),settings.MaxWidth){StartLineCap=PenLineCap.Round,EndLineCap=PenLineCap.Round,LineJoin=PenLineJoin.Round};pen.Freeze();if(e.Points.Count==1)dc.DrawEllipse(color.Brush(alpha),null,e.Points[0].Point,settings.MaxWidth/2,settings.MaxWidth/2);else dc.DrawGeometry(null,pen,path);return;
        }
        var coverage=StrokeGeometry(e);
        if(e.Pen=="Highlighter"){dc.DrawGeometry(color.Brush(alpha),null,coverage);return;}
        if(e.Pen is "Pencil" or "Chalk"){
            var darkness=settings.PencilGrade switch{"2H"=>.48,"H"=>.64,"HB"=>.78,"2B"=>.87,"4B"=>.96,_=>1};dc.DrawGeometry(color.Brush(alpha*(e.Pen=="Pencil"?darkness*.10:.14)),null,coverage);dc.PushClip(coverage);for(int i=0;i<e.Points.Count;i++){var p=e.Points[i];var width=BrushMetrics.Width(e,p);for(int j=0;j<(e.Pen=="Pencil"?9:13);j++){var seed=Hash(e.Id,i,j);var radius=(e.Pen=="Pencil"?.12+.55*Noise(seed,1):.25+1.05*Noise(seed,1))*settings.TextureScale;var brush=color.Brush(BrushMetrics.Opacity(e,p)*darkness*(.25+Noise(seed,4)*.6));dc.DrawEllipse(brush,null,new(p.X+(Noise(seed,2)-.5)*width,p.Y+(Noise(seed,3)-.5)*width),radius,radius*(e.Pen=="Pencil"?.55:.85));}}dc.Pop();return;
        }
        if(e.Pen=="Airbrush"){for(var i=0;i<e.Points.Count;i++){var p=e.Points[i];if(i>0&&(p.Point-e.Points[i-1].Point).Length<settings.MaxWidth*.08)continue;var c=color.Brush(BrushMetrics.Opacity(e,p)*.35).Color;var gradient=new RadialGradientBrush(c,Color.FromArgb(0,c.R,c.G,c.B)){RadiusX=.5,RadiusY=.5};gradient.Freeze();var radius=BrushMetrics.Width(e,p)/2;dc.DrawEllipse(gradient,null,p.Point,radius,radius);}return;}
        if(e.Pen=="Calligraphy"){foreach(var p in Resample(e,Math.Max(.8,settings.MaxWidth*.055))){var width=settings.Width(p.Pressure);var along=new Vector(width/Math.Sqrt(8),width/Math.Sqrt(8));var across=new Vector(-width*.075/Math.Sqrt(2),width*.075/Math.Sqrt(2));dc.DrawGeometry(color.Brush(BrushMetrics.Opacity(e,p)),null,Polygon([p.Point-along-across,p.Point+along-across,p.Point+along+across,p.Point-along+across]));}return;}
        // Varying pressure changes both coverage and opacity; source samples remain untouched.
        for(int i=0;i<e.Points.Count;i++) DrawStrokeSegment(dc,e,color,i);
        if(e.Pen=="Marker"){var p=new Pen(color.Brush(alpha*.18),Math.Max(.5,settings.MaxWidth*.09));var offset=settings.MaxWidth*.28;for(var i=1;i<e.Points.Count;i++)dc.DrawLine(p,new(e.Points[i-1].X+offset,e.Points[i-1].Y),new(e.Points[i].X+offset,e.Points[i].Y));}
    }
    public static void DrawStrokeSegment(DrawingContext dc,DrawingElement e,InkColor color,int index)
    {
        var p=e.Points[index];var previous=index>0?e.Points[index-1]:p;var direction=p.Point-previous.Point;var width=BrushMetrics.Width(e,p,direction);var priorWidth=BrushMetrics.Width(e,previous,direction);var brush=color.Brush(BrushMetrics.Opacity(e,p));
        if(e.Pen=="Airbrush"){var c=brush.Color;var gradient=new RadialGradientBrush(Color.FromArgb((byte)(c.A*.35),c.R,c.G,c.B),Color.FromArgb(0,c.R,c.G,c.B));gradient.Freeze();dc.DrawEllipse(gradient,null,p.Point,width/2,width/2);return;}
        if(e.Pen is "Pencil" or "Chalk"){dc.DrawEllipse(color.Brush(BrushMetrics.Opacity(e,p)*.12),null,p.Point,width/2,width/2);for(int j=0;j<12;j++){var seed=Hash(e.Id,index,j);var r=(.12+Noise(seed,1)*.55)*e.EffectiveBrushSettings.TextureScale;dc.DrawEllipse(color.Brush(BrushMetrics.Opacity(e,p)*(.25+Noise(seed,4)*.6)),null,new(p.X+(Noise(seed,2)-.5)*width,p.Y+(Noise(seed,3)-.5)*width),r,r*.65);}return;}
        if(direction.Length>.001){var n=new Vector(-direction.Y,direction.X);n.Normalize();var geometry=Polygon([previous.Point+n*(priorWidth/2),p.Point+n*(width/2),p.Point-n*(width/2),previous.Point-n*(priorWidth/2)]);if(e.Pen=="Dry Erase" && index%4==0){var hole=new EllipseGeometry(new(p.X+width*.34,p.Y),Math.Max(.15,width*.04),Math.Max(.35,width*.14));dc.DrawGeometry(brush,null,new CombinedGeometry(GeometryCombineMode.Exclude,geometry,hole));}else dc.DrawGeometry(brush,null,geometry);}
        dc.DrawEllipse(brush,null,p.Point,width/2,width/2);
    }
    private static Geometry StrokeGeometry(DrawingElement e)
    {
        var group=new GeometryGroup{FillRule=FillRule.Nonzero};for(int i=0;i<e.Points.Count;i++){var p=e.Points[i];var a=i==0?p:e.Points[i-1];var v=p.Point-a.Point;var w=BrushMetrics.Width(e,p,v)/2;var aw=BrushMetrics.Width(e,a,v)/2;group.Children.Add(new EllipseGeometry(p.Point,w,w));if(v.Length>.001){var n=new Vector(-v.Y,v.X);n.Normalize();group.Children.Add(Polygon([a.Point+n*aw,p.Point+n*w,p.Point-n*w,a.Point-n*aw]));}}group.Freeze();return group;
    }
    private static IEnumerable<InkPoint> Resample(DrawingElement e,double spacing){yield return e.Points[0];for(int i=1;i<e.Points.Count;i++){var a=e.Points[i-1];var b=e.Points[i];var steps=Math.Max(1,(int)Math.Ceiling((b.Point-a.Point).Length/spacing));steps=Math.Min(10000,steps);for(int j=1;j<=steps;j++){var t=(double)j/steps;yield return new(a.X+(b.X-a.X)*t,a.Y+(b.Y-a.Y)*t,a.Pressure+(b.Pressure-a.Pressure)*t);}}}
    private static uint Hash(Guid id,int index,int grain){var bytes=id.ToByteArray();return unchecked(BitConverter.ToUInt32(bytes,0)^((uint)index*747796405u)^((uint)grain*2891336453u));}
    private static double Noise(uint seed,uint salt){var x=unchecked(seed+salt*277803737u);x^=x>>16;x*=0x7feb352du;x^=x>>15;x*=0x846ca68bu;x^=x>>16;return x/(double)uint.MaxValue;}
}

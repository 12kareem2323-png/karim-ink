using System.Globalization;
using System.IO;
using System.Text.Json;
namespace KarimEldamatyWindows;

public static class CraftExchange
{
    public static string NativeLink(Board board) => "karimboard://board/" + board.Id.ToString().ToUpperInvariant();
    private static string ElementID(Board board, DrawingElement element) => "karim-" + board.Id.ToString().ToUpperInvariant().ToLowerInvariant() + "-" + element.Id.ToString().ToLowerInvariant();
    public static void ExportExcalidraw(Board board, string path) => File.WriteAllText(path, JsonSerializer.Serialize(Scene(board), new JsonSerializerOptions { WriteIndented = true }));
    public static Dictionary<string,object?> Scene(Board board)
    {
        BoardCodec.Validate(board); var elements = new List<Dictionary<string,object?>>(); var files = new Dictionary<string,object?>();
        foreach (var element in board.Elements.Where(e=>e.Points.Count>0))
        {
            var kind=element.Kind; var first=element.Points[0]; var last=element.Points[^1];
            if(kind is "arc" or "image" or "symbol")
            {
                var bounds=element.Bounds;
                if(bounds.Width>30000||bounds.Height>30000) throw new InvalidDataException("A complex object is too large to preserve in this export. Resize it first.");
                var png=IntegrationRasterAssets.RenderElement(board,element,bounds);var id=ElementID(board,element)+"-asset";var value=Base(element,board,"image");
                value["x"]=bounds.X;value["y"]=bounds.Y;value["width"]=bounds.Width;value["height"]=bounds.Height;value["angle"]=0;value["fileId"]=id;value["status"]="saved";value["scale"]=new[]{1,1};value["crop"]=null;elements.Add(value);
                files[id]=new Dictionary<string,object?>{["id"]=id,["mimeType"]="image/png",["dataURL"]="data:image/png;base64,"+Convert.ToBase64String(png),["created"]=Milliseconds(board.Created),["lastRetrieved"]=Milliseconds(board.Modified)};continue;
            }
            if(kind=="stroke")
            {
                var value=Base(element,board,"freedraw");value["x"]=first.X;value["y"]=first.Y;value["points"]=element.Points.Select(p=>new[]{p.X-first.X,p.Y-first.Y}).ToArray();value["pressures"]=element.Points.Select(p=>p.Pressure).ToArray();value["simulatePressure"]=false;value["strokeWidth"]=element.EffectiveBrushSettings.MaxWidth;value["opacity"]=(int)Math.Round(element.Color.A*element.EffectiveBrushSettings.Opacity*100);value["lastCommittedPoint"]=null;elements.Add(value);
            }
            else if(kind is "line" or "arrow" or "dimension")
            {
                var value=Line(element,board,kind=="line"?"line":"arrow");elements.Add(value);
                if(kind=="dimension")
                {
                    value["startArrowhead"]="arrow";var mm=board.Millimetres(Math.Sqrt(Math.Pow(last.X-first.X,2)+Math.Pow(last.Y-first.Y,2)));var label=new DrawingElement{Kind="text",Points=[new((first.X+last.X)/2,(first.Y+last.Y)/2+17)],Text=mm.ToString("0.##",CultureInfo.InvariantCulture)+" mm",FontSize=Math.Max(16,element.FontSize),Color=element.Color,Rotation=element.Rotation};
                    var caption=Text(label,board);caption["id"]=ElementID(board,element)+"-mm";var group=new[]{ElementID(board,element)+"-dimension"};caption["groupIds"]=group;value["groupIds"]=group;elements.Add(caption);
                }
            }
            else if(kind=="text") elements.Add(Text(element,board));
            else if(kind=="triangle")
            {
                var vertices=element.Points.Count>=3?element.Points.Take(3).ToArray():new[]{new InkPoint((first.X+last.X)/2,Math.Min(first.Y,last.Y)),new InkPoint(Math.Max(first.X,last.X),Math.Max(first.Y,last.Y)),new InkPoint(Math.Min(first.X,last.X),Math.Max(first.Y,last.Y))};
                var value=Line(element,board,"line");value["x"]=vertices[0].X;value["y"]=vertices[0].Y;value["points"]=vertices.Append(vertices[0]).Select(p=>new[]{p.X-vertices[0].X,p.Y-vertices[0].Y}).ToArray();value["polygon"]=true;elements.Add(value);
            }
            else elements.Add(Base(element,board,kind=="ellipse"?"ellipse":"rectangle"));
        }
        return new(){["type"]="excalidraw",["version"]=2,["source"]=NativeLink(board),["elements"]=elements,["files"]=files,["appState"]=new Dictionary<string,object?>{["name"]=board.Title,["viewBackgroundColor"]=Background(board.Background),["gridSize"]=null},["karimEldamaty"]=new{boardID=board.Id.ToString().ToUpperInvariant(),pointsPerMM=board.PointsPerMM,scaleDenominator=board.ScaleDenominator,paper=board.Background,nativeLink=NativeLink(board)}};
    }
    public static IReadOnlyList<Dictionary<string,object?>> VectorElements(Board board)
    {
        if(board.Elements.Any(e=>e.Points.Count>0&&e.Kind is "arc" or "image" or "symbol")) throw new InvalidOperationException("Direct Craft send supports basic pen paths, shapes, text and dimensions. Export Excalidraw or PNG to preserve images and complex diagrams.");
        return (List<Dictionary<string,object?>>)Scene(board)["elements"]!;
    }
    private static Dictionary<string,object?> Base(DrawingElement item,Board board,string type)
    {
        var first=item.Points[0];var last=item.Points[^1];var bounds=item.Bounds;
        if(item.Kind=="stroke"||item.Kind=="triangle")bounds=new System.Windows.Rect(new System.Windows.Point(item.Points.Min(p=>p.X),item.Points.Min(p=>p.Y)),new System.Windows.Point(item.Points.Max(p=>p.X),item.Points.Max(p=>p.Y)));
        else if(item.Kind!="text")bounds=new System.Windows.Rect(new System.Windows.Point(Math.Min(first.X,last.X),Math.Min(first.Y,last.Y)),new System.Windows.Point(Math.Max(first.X,last.X),Math.Max(first.Y,last.Y)));
        var color=ColorHex(item.Color);
        return new(){["id"]=ElementID(board,item),["type"]=type,["x"]=bounds.X,["y"]=bounds.Y,["width"]=Math.Max(0,bounds.Width),["height"]=Math.Max(0,bounds.Height),["angle"]=item.Rotation*Math.PI/180,["strokeColor"]=color,["backgroundColor"]=item.Fill?color:"transparent",["fillStyle"]="solid",["strokeWidth"]=item.Width,["strokeStyle"]=item.Dash=="Dotted"?"dotted":item.Dash=="Solid"?"solid":"dashed",["roughness"]=0,["opacity"]=(int)Math.Round(item.Color.A*100),["seed"]=1,["version"]=1,["versionNonce"]=1,["index"]=null,["isDeleted"]=false,["groupIds"]=Array.Empty<string>(),["frameId"]=null,["roundness"]=null,["boundElements"]=null,["updated"]=Milliseconds(board.Modified),["created"]=Milliseconds(board.Created),["link"]=NativeLink(board),["locked"]=item.Locked,["customData"]=new Dictionary<string,object?>{["app"]="Karim Eldamaty",["boardID"]=board.Id.ToString().ToUpperInvariant(),["elementID"]=item.Id.ToString().ToUpperInvariant(),["nativeKind"]=item.Kind,["pen"]=item.Pen,["nativeLink"]=NativeLink(board),["pointsPerMM"]=board.PointsPerMM,["scaleDenominator"]=board.ScaleDenominator}};
    }
    private static Dictionary<string,object?> Line(DrawingElement item,Board board,string type) { var value=Base(item,board,type);var a=item.Points[0];var b=item.Points[^1];value["x"]=a.X;value["y"]=a.Y;value["points"]=new[]{new[]{0d,0d},new[]{b.X-a.X,b.Y-a.Y}};value["startBinding"]=null;value["endBinding"]=null;value["startArrowhead"]=null;value["endArrowhead"]=type=="arrow"?"arrow":null;value["elbowed"]=false;value["polygon"]=false;return value; }
    private static Dictionary<string,object?> Text(DrawingElement item,Board board) { var value=Base(item,board,"text");value["x"]=item.Points[0].X;value["y"]=item.Points[0].Y;value["fontSize"]=item.FontSize;value["fontFamily"]=2;value["text"]=item.Text;value["originalText"]=item.Text;value["textAlign"]="left";value["verticalAlign"]="top";value["containerId"]=null;value["baseFontSize"]=null;value["autoResize"]=true;value["lineHeight"]=1.4;return value; }
    private static string ColorHex(InkColor c)=>$"#{(int)Math.Round(c.R*255):X2}{(int)Math.Round(c.G*255):X2}{(int)Math.Round(c.B*255):X2}";
    private static long Milliseconds(double swiftDate)=>SwiftDate.ToDate(swiftDate).ToUnixTimeMilliseconds();
    private static string Background(string kind)=>kind=="Blueprint"?"#13335C":kind=="Dark board"?"#1A1F26":"#FEFDF9";
}

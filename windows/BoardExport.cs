using System.Globalization;
using System.Text;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace KarimEldamatyWindows;

public static class BoardExport
{
    public static byte[] RenderSelectionPNG(Board board,IReadOnlySet<Guid> ids)
    {
        var items=board.Elements.Where(e=>ids.Contains(e.Id)).ToArray();var bounds=Rect.Empty;foreach(var e in items)bounds.Union(e.Bounds);
        if(bounds.IsEmpty)throw new InvalidDataException("The selection has no visible objects.");bounds.Inflate(10,10);
        var scale=Math.Min(2,4096/Math.Max(bounds.Width,bounds.Height));scale=Math.Min(scale,Math.Sqrt(16_000_000d/(bounds.Width*bounds.Height)));
        var visual=new DrawingVisual();using(var dc=visual.RenderOpen()){dc.PushTransform(new ScaleTransform(scale,scale));dc.PushTransform(new TranslateTransform(-bounds.X,-bounds.Y));foreach(var e in BoardRenderer.DrawingOrder(items))BoardRenderer.DrawElement(dc,e,board);dc.Pop();dc.Pop();}
        var bmp=new RenderTargetBitmap(Math.Max(1,(int)Math.Ceiling(bounds.Width*scale)),Math.Max(1,(int)Math.Ceiling(bounds.Height*scale)),96,96,PixelFormats.Pbgra32);bmp.Render(visual);bmp.Freeze();var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bmp));using var output=new MemoryStream();encoder.Save(output);return output.ToArray();
    }
    /// Exact paper rectangle by default; cropped integration boards retain their placement.
    public static byte[] RenderPNG(Board board, bool includeOffSheet = false, int maxPixels = 4096)
    {
        var bitmap = RenderBitmap(board,includeOffSheet,maxPixels);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = new MemoryStream(); encoder.Save(stream); return stream.ToArray();
    }
    public static RenderTargetBitmap RenderBitmap(Board board,bool includeOffSheet=false,int maxPixels=4096)
    {
        var bounds = new Rect(0,0,Math.Max(1,board.Width),Math.Max(1,board.Height));
        if (includeOffSheet) foreach (var element in board.Elements) bounds.Union(BoardRenderer.ElementBounds(element));
        var scale = Math.Min(2d,maxPixels/Math.Max(bounds.Width,bounds.Height));
        scale = Math.Min(scale,Math.Sqrt(24_000_000d/(bounds.Width*bounds.Height)));
        var width = Math.Max(1,(int)Math.Ceiling(bounds.Width*scale)); var height = Math.Max(1,(int)Math.Ceiling(bounds.Height*scale));
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            dc.DrawRectangle(board.Background is "Dark board" or "Blueprint" ? new SolidColorBrush(Color.FromRgb(22,30,40)) : Brushes.White,null,new Rect(0,0,width,height));
            dc.PushTransform(new ScaleTransform(scale,scale)); dc.PushTransform(new TranslateTransform(-bounds.X,-bounds.Y));
            if(includeOffSheet)
            {
                // Background remains calibrated to the original paper origin. Ink outside the
                // nominal sheet is included without changing any board coordinates or IDs.
                BoardRenderer.DrawBackground(dc,board,bounds,1);
                foreach(var element in BoardRenderer.DrawingOrder(board.Elements)) BoardRenderer.DrawElement(dc,element,board);
            }
            else dc.DrawDrawing(BoardRenderer.BuildDrawing(board));
            dc.Pop(); dc.Pop();
        }
        var image = new RenderTargetBitmap(width,height,96,96,PixelFormats.Pbgra32); image.Render(visual); image.Freeze(); return image;
    }
    public static void ExportImage(Board board,string path)
    {
        var image=RenderBitmap(board,true,8192);
        BitmapEncoder encoder = Path.GetExtension(path).Equals(".jpg",StringComparison.OrdinalIgnoreCase) || Path.GetExtension(path).Equals(".jpeg",StringComparison.OrdinalIgnoreCase) ? new JpegBitmapEncoder { QualityLevel=94 } : new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(image)); using var file=File.Create(path); encoder.Save(file);
    }
    public static void ExportPDF(Board board,string path)
    {
        var image=RenderBitmap(board,true,8192); var jpeg=new JpegBitmapEncoder { QualityLevel=97 }; jpeg.Frames.Add(BitmapFrame.Create(image));
        using var bytes=new MemoryStream(); jpeg.Save(bytes); var raster=bytes.ToArray();
        var bounds=new Rect(0,0,board.Width,board.Height); foreach(var e in board.Elements) bounds.Union(BoardRenderer.ElementBounds(e));
        var width=Math.Clamp(bounds.Width/board.PointsPerMM*72/25.4,1,14400); var height=Math.Clamp(bounds.Height/board.PointsPerMM*72/25.4,1,14400);
        string F(double n)=>n.ToString("0.#####",CultureInfo.InvariantCulture);
        var content=Encoding.ASCII.GetBytes($"q {F(width)} 0 0 {F(height)} 0 0 cm /Im0 Do Q\n");
        using var file=File.Create(path); var offsets=new List<long>{0};
        void Text(string s) { var b=Encoding.ASCII.GetBytes(s); file.Write(b); }
        void Object(int id,string body) { offsets.Add(file.Position); Text($"{id} 0 obj\n{body}\nendobj\n"); }
        Text("%PDF-1.4\n");
        Object(1,"<< /Type /Catalog /Pages 2 0 R >>");
        Object(2,"<< /Type /Pages /Kids [3 0 R] /Count 1 >>");
        Object(3,$"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {F(width)} {F(height)}] /Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>");
        offsets.Add(file.Position); Text($"4 0 obj\n<< /Type /XObject /Subtype /Image /Width {image.PixelWidth} /Height {image.PixelHeight} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length {raster.Length} >>\nstream\n"); file.Write(raster); Text("\nendstream\nendobj\n");
        offsets.Add(file.Position); Text($"5 0 obj\n<< /Length {content.Length} >>\nstream\n"); file.Write(content); Text("endstream\nendobj\n");
        var xref=file.Position; Text("xref\n0 6\n0000000000 65535 f \n"); foreach(var offset in offsets.Skip(1)) Text(offset.ToString("D10",CultureInfo.InvariantCulture)+" 00000 n \n");
        Text($"trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n");
    }
}

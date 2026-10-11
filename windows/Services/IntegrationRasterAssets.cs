using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
namespace KarimEldamatyWindows;
internal static class IntegrationRasterAssets
{
    public static byte[] RenderElement(Board board,DrawingElement element,Rect bounds)
    {
        var scale=Math.Min(2,2048/Math.Max(1,Math.Max(bounds.Width,bounds.Height)));
        var width=Math.Max(1,(int)Math.Ceiling(bounds.Width*scale));var height=Math.Max(1,(int)Math.Ceiling(bounds.Height*scale));
        var visual=new DrawingVisual();using(var dc=visual.RenderOpen())
        {
            dc.PushTransform(new ScaleTransform(scale,scale));dc.PushTransform(new TranslateTransform(-bounds.X,-bounds.Y));
            dc.DrawDrawing(BoardRenderer.BuildElement(element,board));dc.Pop();dc.Pop();
        }
        var bitmap=new RenderTargetBitmap(width,height,96,96,PixelFormats.Pbgra32);bitmap.Render(visual);var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));using var memory=new MemoryStream();encoder.Save(memory);return memory.ToArray();
    }
}

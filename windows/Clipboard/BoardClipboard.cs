using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media.Imaging;
namespace KarimEldamatyWindows;

public static class BoardClipboard
{
    public static bool Copy(DrawingSession session)
    {
        try
        {
            var json=SelectionCodec.Encode(session.Board,session.SelectedIds);var copied=SelectionCodec.Decode(json);
            var data=new DataObject();data.SetData(SelectionCodec.Format,json);
            var plain=SelectionCodec.PlainText(copied);if(plain.Length>0)data.SetText(plain,TextDataFormat.UnicodeText);
            // A standard bitmap lets Word, Craft, Notion and other image-capable applications paste a copy.
            var png=BoardExport.RenderSelectionPNG(session.Board,session.SelectedIds);
            using var stream=new MemoryStream(png);var bitmap=BitmapFrame.Create(stream,BitmapCreateOptions.PreservePixelFormat,BitmapCacheOption.OnLoad);bitmap.Freeze();data.SetImage(bitmap);
            data.SetData("PNG",new MemoryStream(png,false));System.Windows.Clipboard.SetDataObject(data,true);
            session.Status("Copied editable objects, image and available text.");return true;
        }
        catch(Exception ex)when(ex is ExternalException or InvalidDataException or ArgumentException or IOException){session.Status(ex.Message);return false;}
    }
    public static bool Cut(DrawingSession session)
    {
        if(!Copy(session))return false;
        session.DeleteSelection();session.Status("Cut copied objects. Locked originals were kept.");return true;
    }
    public static void Paste(DrawingSession session,BoardCanvas canvas)
    {
        canvas.FinishStroke();
        try
        {
            var point=canvas.WorldPoint(new(Math.Max(40,canvas.ActualWidth/2-100),Math.Max(40,canvas.ActualHeight/2-100)));
            if(System.Windows.Clipboard.ContainsData(SelectionCodec.Format)&&System.Windows.Clipboard.GetData(SelectionCodec.Format) is string json){var count=SelectionCodec.Paste(session,json,point.X,point.Y);session.Status($"Pasted {count} editable objects.");return;}
            if(System.Windows.Clipboard.ContainsImage())
            {var image=System.Windows.Clipboard.GetImage();if(image is null)return;if((long)image.PixelWidth*image.PixelHeight>32_000_000)throw new InvalidDataException("Clipboard image exceeds 32 million pixels. Import a smaller image file.");var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(image));using var stream=new MemoryStream();encoder.Save(stream);canvas.AddImage(stream.ToArray(),point);session.Status("Pasted image.");return;}
            if(System.Windows.Clipboard.ContainsText())
            {var text=System.Windows.Clipboard.GetText();if(text.Length>100000)throw new InvalidDataException("Clipboard text exceeds 100,000 characters.");session.AddText(text,point.X,point.Y);session.Status("Pasted editable text.");return;}
            session.Status("The clipboard has no drawing objects, image or text to paste.");
        }
        catch(Exception ex)when(ex is ExternalException or InvalidDataException or ArgumentException or IOException or System.Text.Json.JsonException){session.Status(ex.Message);}
    }
}

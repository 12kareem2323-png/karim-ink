using System.Globalization;
using System.Buffers.Binary;
using System.Runtime.InteropServices;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage.Streams;
using BitmapDecoder = Windows.Graphics.Imaging.BitmapDecoder;
using BitmapFrame = System.Windows.Media.Imaging.BitmapFrame;

namespace KarimEldamatyWindows;
public sealed record LocalOCRResult(string Text, string Language);
public static class HandwritingRecognitionService
{
    private static readonly SemaphoreSlim gate=new(1,1);
    /// <summary>Windows OCR processes a bounded PNG locally. It may miss handwriting; review is always required.</summary>
    public static async Task<LocalOCRResult> RecognizeAsync(byte[] png, CancellationToken cancellationToken)
    {
        LocalPng.Validate(png);
        cancellationToken.ThrowIfCancellationRequested();
        await gate.WaitAsync(cancellationToken);
        try
        {
            if (!HasPackageIdentity) return await RecognizeTesseractAsync(png,cancellationToken);
            try { return await RecognizeWindowsAsync(png,cancellationToken); }
            catch (OperationCanceledException) { throw; }
            catch (Exception ex) when (ex is InvalidOperationException or System.Runtime.InteropServices.COMException) { return await RecognizeTesseractAsync(png,cancellationToken); }
        }
        finally { gate.Release(); }
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] private static extern int GetCurrentPackageFullName(ref uint length, IntPtr name);
    public static bool HasPackageIdentity { get { if(!OperatingSystem.IsWindows())return false;uint length=0;return GetCurrentPackageFullName(ref length,IntPtr.Zero)==122&&length>0; } }
    private static Task<LocalOCRResult> RecognizeTesseractAsync(byte[] png,CancellationToken cancellationToken) => Task.Run(() =>
    {
        cancellationToken.ThrowIfCancellationRequested(); var directory=Path.Combine(AppContext.BaseDirectory,"Resources","OCR");
        if(!File.Exists(Path.Combine(directory,"eng.traineddata")))throw new FileNotFoundException("The local OCR language data is missing. Reinstall the app.");
        try
        {
            using var engine=new Tesseract.TesseractEngine(directory,"eng",Tesseract.EngineMode.LstmOnly);
            engine.SetVariable("user_defined_dpi","300");using var image=Tesseract.Pix.LoadFromMemory(png);using var page=engine.Process(image,Tesseract.PageSegMode.Auto);
            var text=page.GetText().Trim();cancellationToken.ThrowIfCancellationRequested();return new LocalOCRResult(text,"Tesseract English · local CPU");
        }
        catch (Exception ex) when (ex is DllNotFoundException or BadImageFormatException or TypeInitializationException)
        { throw new InvalidOperationException("Local OCR needs the Microsoft Visual C++ 2015–2022 x64 runtime. Install the current Visual C++ x64 runtime from Microsoft’s official website, reopen this app, and try again. You can still type and insert a reviewed transcription.",ex); }
    },cancellationToken);
    private static async Task<LocalOCRResult> RecognizeWindowsAsync(byte[] png, CancellationToken cancellationToken)
    {
        var engine = OcrEngine.TryCreateFromUserProfileLanguages() ?? OcrEngine.TryCreateFromLanguage(new Windows.Globalization.Language("en-GB"));
        if (engine == null) throw new InvalidOperationException("Windows OCR has no installed language. Add English in Windows Settings → Time & language → Language & region, then try again.");
        using var stream = new InMemoryRandomAccessStream();
        using (var writer = new DataWriter(stream)) { writer.WriteBytes(png); await writer.StoreAsync().AsTask(cancellationToken); writer.DetachStream(); }
        stream.Seek(0); var decoder = await BitmapDecoder.CreateAsync(stream).AsTask(cancellationToken);
        var largest = Math.Min(2048u, OcrEngine.MaxImageDimension); var scale = Math.Min(1, largest / (double)Math.Max(decoder.PixelWidth, decoder.PixelHeight));
        var transform = new BitmapTransform { ScaledWidth = Math.Max(1u, (uint)(decoder.PixelWidth * scale)), ScaledHeight = Math.Max(1u, (uint)(decoder.PixelHeight * scale)) };
        using var bitmap = await decoder.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore, transform, ExifOrientationMode.IgnoreExifOrientation, ColorManagementMode.DoNotColorManage).AsTask(cancellationToken);
        var result = await engine.RecognizeAsync(bitmap).AsTask(cancellationToken); cancellationToken.ThrowIfCancellationRequested();
        return new(string.Join(Environment.NewLine, result.Lines.Select(x => x.Text)), "Windows OCR · " + engine.RecognizerLanguage.DisplayName);
    }
}

internal static class InkPreviewRenderer
{
    public static byte[] Render(IReadOnlyList<DrawingElement> strokes)
    {
        if (strokes.Count == 0) throw new InvalidOperationException("Select handwriting strokes on the drawing first.");
        if (strokes.Count > 2048 || strokes.Sum(x => (long)x.Points.Count) > 100000) throw new InvalidOperationException("Select a smaller handwriting area (at most 2,048 strokes and 100,000 points).");
        var points = strokes.SelectMany(x => x.Points).ToArray();
        if (points.Length == 0 || points.Any(p => !double.IsFinite(p.X) || !double.IsFinite(p.Y) || Math.Abs(p.X) > 1e9 || Math.Abs(p.Y) > 1e9)) throw new InvalidOperationException("This handwriting area has invalid coordinates.");
        var left = points.Min(x => x.X); var top = points.Min(x => x.Y); var width = Math.Max(1, points.Max(x => x.X) - left); var height = Math.Max(1, points.Max(x => x.Y) - top);
        var scale = Math.Min(3, 1984 / Math.Max(width, height)); var pw = Math.Max(64, (int)Math.Ceiling(width * scale + 64)); var ph = Math.Max(64, (int)Math.Ceiling(height * scale + 64));
        var visual = new DrawingVisual(); using (var dc = visual.RenderOpen())
        {
            dc.DrawRectangle(Brushes.White, null, new Rect(0, 0, pw, ph));
            foreach (var stroke in strokes)
            {
                var pen = new Pen(Brushes.Black, Math.Clamp(stroke.Width * scale, 1.8, 12)) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
                var path = new StreamGeometry(); using (var context = path.Open()) { if (stroke.Points.Count > 0) { var first = stroke.Points[0]; context.BeginFigure(new Point((first.X - left) * scale + 32, (first.Y - top) * scale + 32), false, false); context.PolyLineTo(stroke.Points.Skip(1).Select(p => new Point((p.X - left) * scale + 32, (p.Y - top) * scale + 32)).ToArray(), true, false); } }
                if (stroke.Points.Count == 1) { var p = stroke.Points[0]; dc.DrawEllipse(Brushes.Black, null, new Point((p.X-left)*scale+32,(p.Y-top)*scale+32), pen.Thickness/2, pen.Thickness/2); } else dc.DrawGeometry(null, pen, path);
            }
        }
        var bitmap = new RenderTargetBitmap(pw, ph, 96, 96, PixelFormats.Pbgra32); bitmap.Render(visual); var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap)); using var memory = new MemoryStream(); encoder.Save(memory); return memory.ToArray();
    }
}

public sealed class HandwritingReviewWindow : Window
{
    private readonly DrawingSession session;
    private readonly Guid boardId;
    private HashSet<Guid> ids;
    private DrawingElement[] original;
    private readonly CheckBox livePreview = ServiceUI.Check("Preview new ink locally after 2 seconds of quiet");
    private readonly TextBlock previewSuggestion = ServiceUI.Text("Local preview is off. It never changes your drawing or reviewed text automatically.", 12, true);
    private readonly DispatcherTimer previewTimer = new() { Interval = TimeSpan.FromSeconds(2) };
    private readonly Image inkImage = new() { MaxHeight = 180, Stretch = Stretch.Uniform, Margin = new Thickness(0,0,0,10) };
    private DrawingElement[] latestPreviewInk = [];
    private HashSet<Guid> latestPreviewIds = [];
    private string latestPreviewText = "";
    private readonly TextBox text = ServiceUI.Input("", true);
    private readonly TextBlock status = ServiceUI.Text("Ready for local OCR", 12, true);
    private readonly Button recognize, insert, replace;
    private CancellationTokenSource? pending;
    private bool edited;
    private int appliedRevision;
    public HandwritingReviewWindow(DrawingSession session)
    {
        SetResourceReference(StyleProperty, typeof(Window));
        this.session = session; boardId = session.Board.Id;
        // Replacement is limited to the strokes explicitly selected when this review opens.
        original = session.Board.Elements.Where(e => e.Kind == "stroke" && (session.SelectedIds.Count == 0 || session.SelectedIds.Contains(e.Id))).Select(BoardCodec.Clone).ToArray();
        ids = session.SelectedIds.Count == 0 ? [] : original.Select(e => e.Id).ToHashSet();
        Title = "Handwriting review · local OCR"; Width = 720; Height = 700; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        SetResourceReference(BackgroundProperty, "SurfaceBrush");
        var stack = new StackPanel { Margin = new Thickness(20) }; stack.Children.Add(ServiceUI.Text("Review handwriting", 23)); stack.Children.Add(ServiceUI.Text("OCR runs on this PC. The portable app uses bundled Tesseract; packaged installs can use Windows OCR. Neat printed writing works best. Handwriting, equations and small writing can be misread. Review every number, decimal point, symbol and unit. Original ink stays until you choose Replace selected ink.", 13, true));
        try { var png = InkPreviewRenderer.Render(original); var preview = new BitmapImage(); preview.BeginInit(); preview.CacheOption = BitmapCacheOption.OnLoad; preview.StreamSource = new MemoryStream(png); preview.EndInit(); preview.Freeze(); inkImage.Source = preview; stack.Children.Add(inkImage); }
        catch (Exception ex) { status.Text = ex.Message; }
        recognize = ServiceUI.Button("Recognize locally", () => _ = RecognizeAsync()); stack.Children.Add(recognize); stack.Children.Add(status);
        stack.Children.Add(livePreview); stack.Children.Add(previewSuggestion); stack.Children.Add(ServiceUI.Button("Use latest local preview for review", UseLatestPreview));
        livePreview.Checked += (_,_) => SchedulePreview(); livePreview.Unchecked += (_,_) => previewTimer.Stop();
        previewTimer.Tick += (_,_) => { previewTimer.Stop(); if(IsVisible && livePreview.IsChecked == true) _ = PreviewAsync(); };
        session.Changed += ObserveBoard;
        text.MinHeight = 200; text.Language = System.Windows.Markup.XmlLanguage.GetLanguage("en-GB"); SpellCheck.SetIsEnabled(text, true); text.TextChanged += (_, _) => UpdateButtons(); stack.Children.Add(text);
        stack.Children.Add(ServiceUI.Text("Right-click underlined words for Windows spelling suggestions. Spelling does not verify engineering terminology or units.", 11, true));
        var row = new WrapPanel(); insert = ServiceUI.Button("Insert text (keep ink)", () => Apply(false)); replace = ServiceUI.Button("Replace selected ink", () => Apply(true)); row.Children.Add(insert); row.Children.Add(replace); row.Children.Add(ServiceUI.Button("Undo board change", Undo)); row.Children.Add(ServiceUI.Button("Cancel OCR", () => pending?.Cancel())); stack.Children.Add(row);
        stack.Children.Add(ServiceUI.Text(ids.Count == 0 ? "No explicit ink selection: you can insert reviewed text; replacement is disabled. Select ink and reopen this window to replace it." : "Only the originally selected, unlocked ink will be replaced. Undo restores it.", 11, true));
        Content = new ScrollViewer { Content = stack, VerticalScrollBarVisibility = ScrollBarVisibility.Auto }; UpdateButtons(); Closed += (_, _) => { previewTimer.Stop(); pending?.Cancel(); session.Changed -= ObserveBoard; }; IsVisibleChanged += (_,_) => { if(!IsVisible) { previewTimer.Stop(); pending?.Cancel(); } };
    }
    private void ObserveBoard()
    {
        if(session.Board.Id != boardId) { livePreview.IsChecked = false; pending?.Cancel(); previewSuggestion.Text = "The drawing changed. Reopen handwriting review for this drawing."; return; }
        if(livePreview.IsChecked == true && IsVisible) SchedulePreview(); UpdateButtons();
    }
    private void SchedulePreview() { previewTimer.Stop(); if(IsVisible && livePreview.IsChecked == true) previewTimer.Start(); }
    private async Task PreviewAsync()
    {
        if(pending != null) { SchedulePreview(); return; }
        if(session.Board.Id != boardId) return;
        var captured = session.Board.Elements.Where(e=>e.Kind=="stroke" && (session.SelectedIds.Count==0 || session.SelectedIds.Contains(e.Id))).Select(BoardCodec.Clone).ToArray();
        var capturedIds = session.SelectedIds.Count == 0 ? new HashSet<Guid>() : captured.Select(e=>e.Id).ToHashSet();
        var revision = session.Revision; pending = new CancellationTokenSource(); recognize.IsEnabled = false; UpdateButtons(); previewSuggestion.Text = "Reading new ink locally…";
        try
        {
            var result = await HandwritingRecognitionService.RecognizeAsync(InkPreviewRenderer.Render(captured), pending.Token);
            if(session.Board.Id != boardId || session.Revision != revision) { previewSuggestion.Text = "Ink changed while reading; waiting for quiet to refresh."; SchedulePreview(); return; }
            latestPreviewInk = captured; latestPreviewIds = capturedIds; latestPreviewText = result.Text;
            previewSuggestion.Text = result.Text.Length == 0 ? "No text found in the latest local preview. Try larger printed writing." : result.Language + " preview: " + (result.Text.Length>700 ? result.Text[..700]+"…" : result.Text) + "\nChoose Use latest local preview to review it. Original ink is unchanged.";
        }
        catch(OperationCanceledException) { previewSuggestion.Text = "Local preview stopped. Original ink is unchanged."; }
        catch(Exception ex) { livePreview.IsChecked=false;previewSuggestion.Text=ex.Message; }
        finally { pending.Dispose(); pending=null; recognize.IsEnabled=true; UpdateButtons(); }
    }
    private void UseLatestPreview()
    {
        if(session.Board.Id != boardId || latestPreviewText.Length==0) { status.Text = "Wait for a local preview containing text first."; return; }
        original=latestPreviewInk.Select(BoardCodec.Clone).ToArray(); ids=new(latestPreviewIds); text.Text=latestPreviewText;
        try { var png=InkPreviewRenderer.Render(original);var image=new BitmapImage();image.BeginInit();image.CacheOption=BitmapCacheOption.OnLoad;image.StreamSource=new MemoryStream(png);image.EndInit();image.Freeze();inkImage.Source=image; } catch(Exception ex) { status.Text=ex.Message;return; }
        status.Text = "Latest local preview copied into review. Check numbers, symbols and units before inserting or replacing.";UpdateButtons();
    }
    private void UpdateButtons() { if (insert == null || replace == null) return; insert.IsEnabled = pending == null && text.Text.Trim().Length > 0; replace.IsEnabled = insert.IsEnabled && ids.Count > 0 && original.All(e => !e.Locked) && ids.All(id => session.Board.Elements.Any(e => e.Id == id && e.Kind == "stroke")); }
    private async Task RecognizeAsync()
    {
        if (pending != null) return; pending = new CancellationTokenSource(); recognize.IsEnabled = false; UpdateButtons(); status.Text = "Reading locally on this Windows PC…";
        try { var result = await HandwritingRecognitionService.RecognizeAsync(InkPreviewRenderer.Render(original), pending.Token); text.Text = result.Text; status.Text = result.Text.Length == 0 ? "No text found. Type a reviewed transcription, or try larger and clearer handwriting." : "Local OCR complete · " + result.Language + ". Check the transcription before inserting."; }
        catch (OperationCanceledException) { status.Text = "OCR cancelled. Original ink is unchanged."; }
        catch (Exception ex) { status.Text = ex.Message; }
        finally { pending.Dispose(); pending = null; recognize.IsEnabled = true; UpdateButtons(); }
    }
    private void Apply(bool replaceInk)
    {
        if (session.Board.Id != boardId) { status.Text = "The open drawing changed. Reopen review for this drawing."; return; }
        if (text.Text.Length > 50000) { status.Text = "Use fewer than 50,000 text characters."; return; }
        if (replaceInk && (ids.Count == 0 || ids.Any(id => !session.Board.Elements.Any(e => e.Id == id && e.Kind == "stroke" && !e.Locked)))) { status.Text = "The original selection is missing or locked. Reopen review with the ink selected."; return; }
        if (replaceInk && original.Any(old => { var current = session.Board.Elements.First(e => e.Id == old.Id); return System.Text.Json.JsonSerializer.Serialize(old, BoardCodec.Options) != System.Text.Json.JsonSerializer.Serialize(current, BoardCodec.Options); })) { status.Text = "Selected ink changed during review. Reopen this window to review the current ink."; return; }
        var bounds = original.SelectMany(e => e.Points).ToArray(); var x = bounds.Length > 0 ? bounds.Min(p => p.X) : 70; var y = bounds.Length > 0 ? bounds.Min(p => p.Y) : 70;
        if (replaceInk)
        {
            session.Checkpoint(); session.Board.Elements.RemoveAll(e => ids.Contains(e.Id) && e.Kind == "stroke");
            session.Board.Elements.Add(new DrawingElement { Kind = "text", Text = text.Text.Trim(), Points = [new InkPoint(x, y)], FontSize = 24 }); session.SelectedIds.Clear(); session.NotifyChanged();
        }
        else session.AddText(text.Text.Trim(), x, y + (bounds.Length > 0 ? bounds.Max(p => p.Y)-y+30 : 0), 24);
        edited = true; appliedRevision = session.Revision; UpdateButtons(); status.Text = replaceInk ? "Selected ink replaced with reviewed text. Undo restores it." : "Text inserted; original ink kept. Undo is available.";
    }
    private void Undo() { if (!edited) return; if (session.Board.Id != boardId || session.Revision != appliedRevision) { status.Text = "Other board edits occurred. Use the main Undo control to review those changes first."; return; } session.Undo(); edited = false; UpdateButtons(); status.Text = "Review change undone."; }
}

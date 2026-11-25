using System.Diagnostics;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using PdfSharp.Drawing;
using PdfSharp.Pdf;
using PdfSharp.Pdf.IO;
using UglyToad.PdfPig.Fonts.Standard14Fonts;
using PdfPoint = UglyToad.PdfPig.Core.PdfPoint;
using UglyToad.PdfPig.Writer;

namespace KarimEldamatyWindows;

internal static class WindowsReleaseChecks
{
    public static async Task InkAsync(MainWindow window, string output)
    {
        await window.NewBoardAsync();
        var session = window.Session;
        session.Tool = "Draw";
        session.SetPen("Technical Fineliner");
        session.ShapeMode = InkShapeMode.OnRelease;
        session.LearnedInkSmoothing = true;
        var samples = Enumerable.Range(0, 80).Select(index =>
            new Point(90 + index * 4, 155 + Math.Sin(.42 * index) * 1.1)).ToArray();
        window.Canvas.BeginInput(samples[0], stylus: false);
        foreach (var point in samples.Skip(1)) window.Canvas.MoveInput(point, sample: null);
        window.Canvas.FinishStroke();
        Require(session.Board.Elements is [{ Kind: "line" }] && session.SelectedIds.Count == 0,
            "A freehand line did not snap cleanly or appeared selected.");
        session.Undo();
        Require(session.Board.Elements is [{ Kind: "stroke" } original] &&
                original.Points.Count == samples.Length &&
                original.Extra?.ContainsKey("windowsOriginalSamples") == true &&
                session.SelectedIds.Count == 0, "First Undo did not restore unselected ink with original samples.");
        session.Redo();
        Require(session.Board.Elements is [{ Kind: "line" }], "Redo did not restore the straightened line.");

        session.ShapeMode = InkShapeMode.Hold;
        window.Canvas.BeginInput(new Point(90, 280), stylus: false);
        foreach (var sample in samples.Skip(1)) window.Canvas.MoveInput(new Point(sample.X, sample.Y + 125), null);
        await Task.Delay(480);
        window.Canvas.FinishStroke();
        Require(session.Board.Elements.Count == 2 && session.Board.Elements[^1].Kind == "line",
            "The 360 ms hold did not snap the second line.");

        var timings = new double[320];
        for (var i = 0; i < timings.Length; i++)
        {
            var started = Stopwatch.GetTimestamp();
            _ = InkShapeRecognizer.Detect(samples, 1, InkShapeMode.OnRelease);
            timings[i] = Stopwatch.GetElapsedTime(started).TotalMilliseconds;
        }
        Array.Sort(timings);
        File.WriteAllText(Path.Combine(output,"shape-fit-timing.json"), JsonSerializer.Serialize(new
        {
            samples = samples.Length, iterations = timings.Length,
            p50Millis = timings[timings.Length / 2], p95Millis = timings[(int)(timings.Length * .95) - 1],
            scope = "Geometry fit only. Does not measure display refresh or input latency."
        }));
    }

    public static async Task PdfAsync(MainWindow window, string output, Action<Window, string> capture)
    {
        var basePath = Path.Combine(output, "base-fixture.pdf");
        var source = Path.Combine(output, "source-fixture.pdf");
        var export = Path.Combine(output, "annotated-pages-1-3.pdf");
        var builder = new PdfDocumentBuilder();
        var font = builder.AddStandard14Font(Standard14Font.Helvetica);
        for (var i = 1; i <= 3; i++)
        {
            var page = builder.AddPage(300, 400);
            page.AddText($"Velin selectable source {i}", 15, new PdfPoint(50, 325), font);
        }
        File.WriteAllBytes(basePath, builder.Build());
        using (var read = PdfReader.Open(basePath, PdfDocumentOpenMode.Modify))
        {
            read.Pages[2].Rotate = 90;
            read.Pages[2].CropBox = new PdfRectangle(new XPoint(20, 24), new XPoint(280, 374));
            read.Save(source);
        }
        var bytes = File.ReadAllBytes(source);
        var book = new PdfBook(window.Store);
        var imported = await book.ImportAsync(source);
        var first = await book.GetPageAsync(imported, 1);
        var third = await book.GetPageAsync(imported, 3);
        Require(imported.Count == 3 && first.Id != third.Id && first.Elements[0].Locked, "PDF page opening failed.");
        var text = await PdfBook.ReadTextAsync(book.Original(imported), 3, CancellationToken.None);
        Require(text.Contains("Velin selectable source 3"), "Select and copy source text failed.");
        var matches = await PdfBook.FindTextAsync(book.Original(imported), "SELECTABLE SOURCE 2", CancellationToken.None);
        Require(matches.Matches is [{ Page: 2 }], "Search returned the wrong source page.");
        var ranges = PdfBook.ParsePages("3, 1–1, 3", imported.Count);
        Require(ranges.SequenceEqual([1, 3]), "Page range was not sorted and deduplicated.");

        var archived = book.Original(imported);
        var sheet = PdfSheet.Read(third)!;
        third.Elements.Add(new DrawingElement
        {
            Kind = "line", Width = 8, Color = new InkColor(.94,.10,.25),
            Points = [new(third.Width * .10, third.Height * .22), new(third.Width * .30, third.Height * .22)]
        });
        await book.ExportAsync(sheet, ranges, third, export);
        var exported = await PdfBook.OpenAsync(export);
        Require(exported.PageCount == 2 &&
            (await PdfBook.ReadTextAsync(export, 2, CancellationToken.None)).Contains("Velin selectable source 3"),
            "Range export did not preserve source text and page order.");
        var bitmap = await PdfBook.ThumbnailAsync(exported, 2);
        Require(HasRed(bitmap, .20, .22), "The annotation did not align with the rotated and cropped page.");
        try
        {
            await book.ExportAsync(sheet, ranges, third, source);
            throw new InvalidOperationException("The export attempted to replace the original PDF.");
        }
        catch (IOException) { }
        Require(File.ReadAllBytes(source).SequenceEqual(bytes) && File.ReadAllBytes(archived).SequenceEqual(bytes),
            "The source PDF changed.");
        await window.OpenBoardAsync(third);
        var browser = new PdfPagesWindow(sheet, archived) { Owner = window };
        browser.Show();
        try
        {
            await Task.Delay(700);
            capture(browser, Path.Combine(output, "pdf-browser.png"));
        }
        finally { browser.Close(); }
        capture(window, Path.Combine(output, "pdf-workspace.png"));
    }

    public static Task PapersAsync(string output)
    {
        var names = Board.BackgroundNames;
        Require(names.Length == 16, "Paper catalogue does not contain all 16 patterns.");
        var sample = new DrawingVisual();
        const int width = 224, height = 144;
        using (var dc = sample.RenderOpen())
        {
            for (var i = 0; i < names.Length; i++)
            {
                // Render real paper geometry and add the names for screenshot inspection.
                var paper = new Board { Width = width, Height = height, Background = names[i], GridSpacing = 20 };
                dc.PushTransform(new TranslateTransform(i % 4 * width, i / 4 * (height + 28)));
                BoardRenderer.DrawBackground(dc, paper, new Rect(0, 0, width, height), 1);
                dc.DrawRectangle(Brushes.White, null, new Rect(0, height, width, 28));
                BoardRenderer.DrawText(dc, names[i], new Point(8, height + 5), 14, InkColor.Graphite);
                dc.Pop();
            }
        }
        var bitmap = new RenderTargetBitmap(width * 4, (height + 28) * 4, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(sample);
        var png = new PngBitmapEncoder();
        png.Frames.Add(BitmapFrame.Create(bitmap));
        using var file = File.Create(Path.Combine(output, "paper-patterns.png"));
        png.Save(file);
        return Task.CompletedTask;
    }

    private static bool HasRed(BitmapSource source, double x, double y)
    {
        var bitmap = new FormatConvertedBitmap(source, PixelFormats.Bgra32, null, 0);
        var stride = bitmap.PixelWidth * 4;
        var pixels = new byte[stride * bitmap.PixelHeight];
        bitmap.CopyPixels(pixels, stride, 0);
        var (centerX, centerY) = ((int)(x * bitmap.PixelWidth), (int)(y * bitmap.PixelHeight));
        for (var row = centerY - 5; row <= centerY + 5; row++)
        for (var column = centerX - 8; column <= centerX + 8; column++)
        {
            var at = row * stride + column * 4;
            if (at >= 0 && at + 3 < pixels.Length && pixels[at + 2] > 170 && pixels[at + 1] < 105)
                return true;
        }
        return false;
    }

    private static void Require(bool condition, string failure)
    {
        if (!condition) throw new InvalidDataException(failure);
    }
}

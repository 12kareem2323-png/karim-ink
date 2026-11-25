using System.Security.Cryptography;
using System.Text.Json;
using System.Windows.Media.Imaging;
using PdfSharp.Drawing;
using PdfSharp.Pdf.IO;
using UglyToad.PdfPig.DocumentLayoutAnalysis.TextExtractor;
using Windows.Data.Pdf;
using Windows.Storage;
using Windows.Storage.Streams;

namespace KarimEldamatyWindows;

internal sealed record PdfSheet(string Digest, string Name, int Count, int Number, Guid ImageId)
{
    internal const string BoardKey = "velinWindowsPdfPage";

    public static PdfSheet? Read(Board board)
    {
        if (board.Extra?.TryGetValue(BoardKey, out var data) != true) return null;
        try
        {
            var page = data.Deserialize<PdfSheet>(BoardCodec.Options);
            return page is { Digest.Length: 64, Name.Length: > 0 and <= 255, Number: > 0, Count: > 0 } &&
                   page.Number <= page.Count && page.Digest.All(Uri.IsHexDigit) ? page : null;
        }
        catch (JsonException) { return null; }
    }
}

internal sealed class PdfBook(BoardStore store)
{
    private const long MaxSourceBytes = 200L * 1024 * 1024;
    private string Originals => Path.Combine(store.DirectoryPath, "PDF Originals");
    internal sealed record TextMatch(int Page, string Excerpt);

    public string Original(PdfSheet sheet) => Path.Combine(Originals, sheet.Digest.ToUpperInvariant() + ".pdf");

    public async Task<PdfSheet> ImportAsync(string source)
    {
        Directory.CreateDirectory(Originals);
        var pending = Path.Combine(Originals, Guid.NewGuid().ToString("N") + ".pdf");
        try
        {
            await using (var input = File.Open(Path.GetFullPath(source), FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                if (input.Length is 0 or > MaxSourceBytes)
                    throw new InvalidDataException("Choose a non-empty PDF of up to 200 MB.");
                await using var copy = new FileStream(pending, FileMode.CreateNew, FileAccess.Write,
                    FileShare.None, 64 * 1024, useAsync: true);
                await input.CopyToAsync(copy);
                await copy.FlushAsync();
            }
            var digest = await HashAsync(pending);
            var document = await OpenAsync(pending);
            if (document.PageCount == 0) throw new InvalidDataException("This PDF has no pages.");
            var sheet = new PdfSheet(digest, Path.GetFileName(source), checked((int)document.PageCount), 1, Guid.Empty);
            var target = Original(sheet);
            try { File.Move(pending, target); }
            catch (IOException) when (File.Exists(target))
            {
                if (!StringComparer.OrdinalIgnoreCase.Equals(await HashAsync(target), digest))
                    throw new IOException("The archived PDF failed its integrity check. Its existing copy was preserved.");
            }
            return sheet;
        }
        finally { File.Delete(pending); }
    }

    public Board? Find(PdfSheet sheet, int number) =>
        store.Boards.FirstOrDefault(board => PdfSheet.Read(board) is { } page &&
            page.Number == number && StringComparer.OrdinalIgnoreCase.Equals(page.Digest, sheet.Digest));

    public async Task<Board> GetPageAsync(PdfSheet sheet, int number)
    {
        if (number < 1 || number > sheet.Count) throw new ArgumentOutOfRangeException(nameof(number));
        if (Find(sheet, number) is { } existing) return existing;
        var document = await OpenAsync(Original(sheet));
        var (png, width, height) = await RenderAsync(document, number, 1800);
        var image = new DrawingElement
        {
            Kind = "image", Locked = true, Text = sheet.Name, ImageData = png,
            Points = [new(0, 0), new(width, height)]
        };
        var board = new Board
        {
            Title = $"{Path.GetFileNameWithoutExtension(sheet.Name)} · Page {number}",
            Folder = "PDFs", Background = "Plain", Width = width, Height = height,
            PointsPerMM = 96 / 25.4, Elements = [image]
        };
        board.Title = board.Title[..Math.Min(board.Title.Length, 300)];
        board.Extra = new()
        {
            [PdfSheet.BoardKey] = JsonSerializer.SerializeToElement(
                sheet with { Number = number, ImageId = image.Id }, BoardCodec.Options)
        };
        return await store.SaveAsync(board) ? board : throw new IOException(store.Error ?? "The page could not be saved.");
    }

    public static async Task<PdfDocument> OpenAsync(string path) =>
        await PdfDocument.LoadFromFileAsync(await StorageFile.GetFileFromPathAsync(path));

    public static async Task<BitmapSource> ThumbnailAsync(PdfDocument document, int number)
    {
        var (bytes, _, _) = await RenderAsync(document, number, 220);
        return BoardRenderer.DecodeImage(bytes);
    }

    private static async Task<(byte[] Bytes, double Width, double Height)> RenderAsync(
        PdfDocument document, int number, uint longestEdge)
    {
        using var page = document.GetPage((uint)number - 1);
        var size = page.Size;
        if (!double.IsFinite(size.Width + size.Height) || Math.Min(size.Width, size.Height) < 1 ||
            Math.Max(size.Width, size.Height) > 30000)
            throw new InvalidDataException("The PDF page has unsupported dimensions.");
        using var stream = new InMemoryRandomAccessStream();
        var options = new PdfPageRenderOptions();
        if (size.Width >= size.Height) options.DestinationWidth = longestEdge;
        else options.DestinationHeight = longestEdge;
        await page.RenderToStreamAsync(stream, options);
        if (stream.Size is 0 or > 24 * 1024 * 1024) throw new InvalidDataException("The PDF page could not be rendered.");
        using var reader = new DataReader(stream.GetInputStreamAt(0));
        if (await reader.LoadAsync((uint)stream.Size) != stream.Size) throw new EndOfStreamException();
        var bytes = new byte[(int)stream.Size];
        reader.ReadBytes(bytes);
        return (bytes, size.Width, size.Height);
    }

    public static Task<string> ReadTextAsync(string path, int number, CancellationToken cancellation) =>
        Task.Run(() =>
        {
            using var pdf = UglyToad.PdfPig.PdfDocument.Open(path);
            cancellation.ThrowIfCancellationRequested();
            return Text(pdf, number);
        }, cancellation);

    public static Task<(List<TextMatch> Matches, bool Limit)> FindTextAsync(
        string path, string query, CancellationToken cancellation) => Task.Run(() =>
    {
        using var pdf = UglyToad.PdfPig.PdfDocument.Open(path);
        var matches = new List<TextMatch>();
        for (var number = 1; number <= pdf.NumberOfPages; number++)
        {
            cancellation.ThrowIfCancellationRequested();
            var text = Text(pdf, number);
            var index = text.IndexOf(query, StringComparison.OrdinalIgnoreCase);
            if (index < 0) continue;
            if (matches.Count == 150) return (matches, true);
            var start = Math.Max(0, index - 26);
            var snippet = text.Substring(start, Math.Min(110, text.Length - start))
                .Replace('\n', ' ').Replace('\r', ' ');
            matches.Add(new(number, snippet));
        }
        return (matches, false);
    }, cancellation);

    private static string Text(UglyToad.PdfPig.PdfDocument pdf, int number)
    {
        var text = ContentOrderTextExtractor.GetText(pdf.GetPage(number));
        return text[..Math.Min(text.Length, 250_000)];
    }

    public static int[] ParsePages(string text, int count)
    {
        var pages = new SortedSet<int>();
        foreach (var part in text.Split(','))
        {
            var interval = part.Replace('–', '-').Split('-', StringSplitOptions.TrimEntries);
            if (interval.Length > 2 || !int.TryParse(interval[0], out var first) ||
                !int.TryParse(interval[^1], out var last) || first < 1 || last > count || last < first)
                throw new FormatException($"Use page numbers 1–{count}, for example 1, 3–5.");
            for (var i = first; i <= last; i++) pages.Add(i);
        }
        return pages.ToArray();
    }

    public async Task ExportAsync(PdfSheet sheet, IReadOnlyList<int> pages, Board current, string destination)
    {
        var fullPath = Path.GetFullPath(destination);
        var relative = Path.GetRelativePath(Originals, fullPath);
        if (!Path.IsPathRooted(relative) && !relative.StartsWith(".." + Path.DirectorySeparatorChar, StringComparison.Ordinal))
            throw new IOException("Choose an export location outside the original PDF archive.");
        if (File.Exists(fullPath) && StringComparer.OrdinalIgnoreCase.Equals(await HashAsync(fullPath), sheet.Digest))
            throw new IOException("Choose a different name to protect the original PDF.");

        var annotated = new Dictionary<int, (Board Board, Guid Source)>();
        foreach (var page in pages)
        {
            var board = page == sheet.Number ? current : Find(sheet, page);
            var reference = board is null ? null : PdfSheet.Read(board);
            if (board is not null && reference is not null && board.Elements.Any(e => e.Id != reference.ImageId))
                annotated.Add(page, (BoardCodec.Clone(board), reference.ImageId));
        }
        var original = Original(sheet);
        var temporary = fullPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            // WPF drawing requires an STA. Run the PDF writer off the UI dispatcher.
            await Task.Factory.StartNew(() => WriteExport(original, pages, annotated, temporary),
                CancellationToken.None, TaskCreationOptions.DenyChildAttach, new StaTaskScheduler());
            File.Move(temporary, fullPath, overwrite: true);
        }
        finally { File.Delete(temporary); }
    }

    private static void WriteExport(string original, IReadOnlyList<int> pages,
        IReadOnlyDictionary<int, (Board Board, Guid Source)> annotated, string destination)
    {
        using var input = PdfReader.Open(original, PdfDocumentOpenMode.Import);
        using var output = new PdfSharp.Pdf.PdfDocument();
        foreach (var number in pages)
        {
            var page = output.AddPage(input.Pages[number - 1]);
            if (!annotated.TryGetValue(number, out var notes) ||
                BoardExport.RenderPdfInk(notes.Board, notes.Source) is not { } png) continue;
            using var graphics = XGraphics.FromPdfPage(page, XGraphicsPdfPageOptions.Append);
            using var stream = new MemoryStream(png, writable: false);
            using var image = XImage.FromStream(stream);
            var media = page.MediaBox;
            var crop = page.CropBox;
            if (crop.Width <= 0 || crop.Height <= 0) crop = media;
            var left = crop.X1 - media.X1;
            var top = media.Y2 - crop.Y2;
            var width = crop.Width;
            var height = crop.Height;
            var rotate = (page.Rotate % 360 + 360) % 360;
            var map = rotate switch
            {
                90 => new XMatrix(0, -1, 1, 0, left, top + height),
                180 => new XMatrix(-1, 0, 0, -1, left + width, top + height),
                270 => new XMatrix(0, 1, -1, 0, left + width, top),
                _ => new XMatrix(1, 0, 0, 1, left, top)
            };
            graphics.MultiplyTransform(map);
            if (rotate is 90 or 270) (width, height) = (height, width);
            graphics.DrawImage(image, 0, 0, width, height);
        }
        output.Save(destination);
    }

    private static async Task<string> HashAsync(string path)
    {
        await using var input = File.OpenRead(path);
        return Convert.ToHexString(await SHA256.HashDataAsync(input));
    }

    private sealed class StaTaskScheduler : TaskScheduler
    {
        protected override IEnumerable<Task> GetScheduledTasks() => [];
        protected override bool TryExecuteTaskInline(Task task, bool taskWasPreviouslyQueued) => false;
        protected override void QueueTask(Task task)
        {
            var thread = new Thread(() => TryExecuteTask(task)) { IsBackground = true, Name = "Velin PDF export" };
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
        }
    }
}

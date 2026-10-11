using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace KarimEldamatyWindows;

internal sealed record FormulaLayout(double Width, double Height, double Baseline, Action<DrawingContext, Point> Draw);

public static class FormulaRenderer
{
    public static bool TryValidate(string latex, out string? error)
    {
        try { new FormulaParser(latex).Parse(); error = null; return true; }
        catch (Exception e) when (e is FormatException or InvalidOperationException) { error = e.Message; return false; }
    }
    internal static FormulaLayout Layout(string latex, InkColor color, double fontSize)
    {
        if (!double.IsFinite(fontSize) || fontSize < 6 || fontSize > 144) throw new ArgumentOutOfRangeException(nameof(fontSize), "Formula size must be between 6 and 144.");
        return LayoutNode(new FormulaParser(latex).Parse(), color.Brush(), fontSize);
    }
    private static FormulaLayout LayoutNode(FormulaNode node, Brush color, double font)
    {
        if (node is FormulaText text)
        {
            var formatted = new FormattedText(text.Text, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, new Typeface("Cambria Math"), Math.Max(4, font), color, 1);
            return new FormulaLayout(formatted.WidthIncludingTrailingWhitespace, Math.Max(font, formatted.Height), formatted.Baseline, (dc, p) => dc.DrawText(formatted, p));
        }
        if (node is FormulaRow row)
        {
            var children = row.Children.Select(n => LayoutNode(n, color, font)).ToList();
            var baseline = children.Count == 0 ? font * .8 : children.Max(c => c.Baseline);
            var descent = children.Count == 0 ? font * .2 : children.Max(c => c.Height - c.Baseline);
            return new FormulaLayout(children.Sum(c => c.Width), baseline + descent, baseline, (dc, p) => { var x = p.X; foreach (var child in children) { child.Draw(dc, new Point(x, p.Y + baseline - child.Baseline)); x += child.Width; } });
        }
        if (node is FormulaFraction fraction)
        {
            var top = LayoutNode(fraction.Numerator, color, font * .86); var bottom = LayoutNode(fraction.Denominator, color, font * .86);
            var width = Math.Max(top.Width, bottom.Width) + font * .3; var gap = font * .12; var line = top.Height + gap;
            return new FormulaLayout(width, top.Height + bottom.Height + gap * 3, line + font * .3, (dc, p) => { top.Draw(dc, new Point(p.X + (width - top.Width) / 2, p.Y)); dc.DrawLine(new Pen(color, Math.Max(1, font * .045)), new Point(p.X, p.Y + line), new Point(p.X + width, p.Y + line)); bottom.Draw(dc, new Point(p.X + (width - bottom.Width) / 2, p.Y + line + gap * 2)); });
        }
        if (node is FormulaRoot root)
        {
            var content = LayoutNode(root.Value, color, font); var radical = LayoutNode(new FormulaText("√"), color, Math.Max(font, content.Height * .85)); var pad = font * .12;
            var height = Math.Max(content.Height + pad * 2, radical.Height); var baseline = content.Baseline + pad * 2; var width = radical.Width + content.Width + pad;
            return new FormulaLayout(width, height, baseline, (dc, p) => { radical.Draw(dc, new Point(p.X, p.Y + baseline - radical.Baseline)); content.Draw(dc, new Point(p.X + radical.Width, p.Y + pad * 2)); dc.DrawLine(new Pen(color, Math.Max(1, font * .04)), new Point(p.X + radical.Width * .8, p.Y + pad), new Point(p.X + width, p.Y + pad)); });
        }
        var scripts = (FormulaScripts)node; var @base = LayoutNode(scripts.Base, color, font);
        var sup = scripts.Super == null ? null : LayoutNode(scripts.Super, color, font * .65); var sub = scripts.Sub == null ? null : LayoutNode(scripts.Sub, color, font * .65);
        var rise = sup == null ? 0 : Math.Max(font * .32, sup.Height - font * .15); var baselineValue = @base.Baseline + rise;
        var subY = rise + @base.Baseline + font * .05; var heightValue = Math.Max(rise + @base.Height, subY + (sub?.Height ?? 0));
        return new FormulaLayout(@base.Width + Math.Max(sup?.Width ?? 0, sub?.Width ?? 0) + font * .08, heightValue, baselineValue, (dc, p) => { @base.Draw(dc, new Point(p.X, p.Y + rise)); sup?.Draw(dc, new Point(p.X + @base.Width, p.Y)); sub?.Draw(dc, new Point(p.X + @base.Width, p.Y + subY)); });
    }
    public static byte[] RenderPng(string latex, InkColor color, double fontSize = 32)
    {
        fontSize = double.IsFinite(fontSize) ? Math.Clamp(fontSize, 6, 144) : 32;
        FormulaLayout layout;
        try { layout = Layout(latex, color, fontSize); }
        catch (FormatException) { layout = LayoutNode(new FormulaText(latex.Length > 4096 ? latex[..4096] + "…" : latex), color.Brush(), fontSize); }
        const double margin = 8;
        var scale = Math.Min(1, Math.Min(4096 / (layout.Width + margin * 2), 2048 / (layout.Height + margin * 2)));
        var width = Math.Max(1, (int)Math.Ceiling((layout.Width + margin * 2) * scale)); var height = Math.Max(1, (int)Math.Ceiling((layout.Height + margin * 2) * scale));
        var visual = new DrawingVisual(); using (var context = visual.RenderOpen()) { context.PushTransform(new ScaleTransform(scale, scale)); layout.Draw(context, new Point(margin, margin)); context.Pop(); }
        var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32); bitmap.Render(visual);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap)); using var stream = new MemoryStream(); encoder.Save(stream); return stream.ToArray();
    }
}

public sealed class NativeMathRenderer : FrameworkElement
{
    private string _latex = "";
    public string Latex { get => _latex; set { _latex = value; InvalidateMeasure(); InvalidateVisual(); } }
    public InkColor Color { get; set; } = InkColor.Graphite;
    public double FontSize { get; set; } = 34;
    protected override Size MeasureOverride(Size availableSize)
    {
        try { var layout = FormulaRenderer.Layout(Latex, Color, FontSize); return new Size(Math.Min(availableSize.Width, layout.Width + 32), Math.Min(availableSize.Height, Math.Max(90, layout.Height + 32))); }
        catch { return new Size(Math.Min(500, availableSize.Width), 100); }
    }
    protected override void OnRender(DrawingContext context)
    {
        base.OnRender(context); context.DrawRectangle(Brushes.White, null, new Rect(RenderSize));
        try
        {
            var layout = FormulaRenderer.Layout(Latex, Color, FontSize); var scale = Math.Min(1, Math.Min(Math.Max(1, ActualWidth - 32) / Math.Max(1, layout.Width), Math.Max(1, ActualHeight - 32) / Math.Max(1, layout.Height)));
            context.PushTransform(new TranslateTransform(16, Math.Max(16, (ActualHeight - layout.Height * scale) / 2))); context.PushTransform(new ScaleTransform(scale, scale)); layout.Draw(context, new Point(0, 0)); context.Pop(); context.Pop();
        }
        catch (FormatException)
        {
            var text = new FormattedText(string.IsNullOrWhiteSpace(Latex) ? "Your formula preview" : Latex, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, new Typeface("Consolas"), 16, Brushes.DimGray, 1) { MaxTextWidth = Math.Max(1, ActualWidth - 32), MaxTextHeight = Math.Max(1, ActualHeight - 32), Trimming = TextTrimming.CharacterEllipsis };
            context.DrawText(text, new Point(16, 16));
        }
    }
}

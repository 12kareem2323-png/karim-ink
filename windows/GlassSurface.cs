using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace KarimEldamatyWindows;

/// <summary>
/// Retained glass card: cached vector rim/shadow, no blur, timer, background capture,
/// or offscreen bitmap of its child subtree. DWM supplies the window backdrop.
/// </summary>
public sealed class GlassSurface : Border
{
    public static readonly DependencyProperty ShowShadowProperty = DependencyProperty.Register(nameof(ShowShadow), typeof(bool), typeof(GlassSurface), new FrameworkPropertyMetadata(true, FrameworkPropertyMetadataOptions.AffectsRender));
    public static readonly DependencyProperty SpecularBrushProperty = DependencyProperty.Register(nameof(SpecularBrush), typeof(Brush), typeof(GlassSurface), new FrameworkPropertyMetadata(Brushes.Transparent, FrameworkPropertyMetadataOptions.AffectsRender));
    public bool ShowShadow { get => (bool)GetValue(ShowShadowProperty); set => SetValue(ShowShadowProperty, value); }
    public Brush SpecularBrush { get => (Brush)GetValue(SpecularBrushProperty); set => SetValue(SpecularBrushProperty, value); }
    private DrawingGroup? _shadow;
    private RectangleGeometry? _rim;
    private Size _cachedSize;
    private CornerRadius _cachedRadius;
    private bool _listening;
    public GlassSurface()
    {
        SetResourceReference(SpecularBrushProperty, "SpecularBrush");
        SnapsToDevicePixels = true;
        UseLayoutRounding = true;
        Loaded += (_, _) => { if (!_listening) { WindowsTheme.Changed += ThemeChanged; _listening = true; } ThemeChanged(); };
        Unloaded += (_, _) => { if (_listening) { WindowsTheme.Changed -= ThemeChanged; _listening = false; } };
    }
    private void ThemeChanged() { _shadow = null; InvalidateVisual(); }
    protected override void OnRender(DrawingContext drawing)
    {
        bool glass = WindowsTheme.GlassEffectsEnabled && !SystemParameters.HighContrast;
        if (glass && RenderSize.Width > 1 && RenderSize.Height > 1)
        {
            PrepareGeometry();
            if (ShowShadow && _shadow != null) drawing.DrawDrawing(_shadow);
        }
        base.OnRender(drawing);
        if (glass && _rim != null && SpecularBrush != null)
        {
            double width = .5 / VisualTreeHelper.GetDpi(this).DpiScaleX;
            var pen = new Pen(SpecularBrush, width);
            if (pen.CanFreeze) pen.Freeze();
            drawing.DrawGeometry(null, pen, _rim);
        }
    }
    private void PrepareGeometry()
    {
        if (_rim != null && _cachedSize == RenderSize && _cachedRadius == CornerRadius && (!ShowShadow || _shadow != null)) return;
        _cachedSize = RenderSize;
        _cachedRadius = CornerRadius;
        var size = RenderSize;
        double radius = Math.Min(Math.Min(CornerRadius.TopLeft, Math.Min(CornerRadius.TopRight, Math.Min(CornerRadius.BottomLeft, CornerRadius.BottomRight))), Math.Min(size.Width, size.Height) * .5);
        _rim = new RectangleGeometry(new Rect(.75, .75, Math.Max(0, size.Width - 1.5), Math.Max(0, size.Height - 1.5)), radius, radius); _rim.Freeze();
        if (!ShowShadow) { _shadow = null; return; }
        var shadow = new DrawingGroup();
        using (var drawing = shadow.Open())
        {
            // Six vector outlines avoid DropShadowEffect rerasterising a changing canvas.
            for (int layer = 6; layer >= 1; layer--)
            {
                var brush = new SolidColorBrush(Color.FromArgb((byte)(WindowsTheme.Dark ? 7 : 4), 10, 25, 40)); brush.Freeze();
                var pen = new Pen(brush, layer * 2d); pen.Freeze();
                var geometry = new RectangleGeometry(new Rect(1, 3, Math.Max(0, size.Width - 2), Math.Max(0, size.Height - 2)), radius, radius); geometry.Freeze();
                drawing.DrawGeometry(null, pen, geometry);
            }
        }
        shadow.Freeze(); _shadow = shadow;
    }
}

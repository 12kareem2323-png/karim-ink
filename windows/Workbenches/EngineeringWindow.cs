using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace KarimEldamatyWindows;

internal sealed record FunctionPlot(string Expression, double XMin, double XMax, double YMin, double YMax, List<List<Point>> Paths);

public sealed class EngineeringWindow : Window
{
    private readonly DrawingSession _session;
    private readonly Guid _boardId;
    private readonly TextBox _expression = WorkbenchUI.Field("sqrt(16) + sin(pi/2)", 400);
    private readonly TextBox _xValue = WorkbenchUI.Field("0", 100);
    private readonly TextBlock _answer = WorkbenchUI.Label("", 22);
    private readonly TextBlock _status = WorkbenchUI.Label("Offline tools. Trigonometric functions use radians.");
    private string? _lastCalculation;
    private readonly ComboBox _family = new() { ItemsSource = EngineeringUnitFamily.All, SelectedIndex = 0, Width = 180, Margin = new Thickness(3) };
    private readonly ComboBox _from = new() { Width = 120, Margin = new Thickness(3) };
    private readonly ComboBox _to = new() { Width = 140, Margin = new Thickness(3) };
    private readonly TextBox _unitValue = WorkbenchUI.Field("1", 160);
    private readonly TextBlock _converted = WorkbenchUI.Label("", 22);
    private string? _lastConversion;
    private readonly TextBox _function = WorkbenchUI.Field("sin(x)", 400);
    private readonly TextBox _xmin = WorkbenchUI.Field("-10", 110);
    private readonly TextBox _xmax = WorkbenchUI.Field("10", 110);
    private readonly TextBox _ymin = WorkbenchUI.Field("-5", 110);
    private readonly TextBox _ymax = WorkbenchUI.Field("5", 110);
    private readonly FunctionPlotPreview _plotPreview = new() { MinHeight = 300 };
    private FunctionPlot? _plot;

    public EngineeringWindow(DrawingSession session)
    {
        _session = session; _boardId = session.Board.Id;
        WorkbenchUI.Window(this, "Engineering tools · SketchGlide", 940, 750);
        var root = new DockPanel { Margin = new Thickness(18) };
        var heading = WorkbenchUI.Label("Engineering tools", 26); DockPanel.SetDock(heading, Dock.Top); root.Children.Add(heading);
        DockPanel.SetDock(_status, Dock.Bottom); root.Children.Add(_status);
        var tabs = new TabControl();
        tabs.Items.Add(new TabItem { Header = "Calculator", Content = CalculatorUI() });
        tabs.Items.Add(new TabItem { Header = "Unit conversion", Content = UnitsUI() });
        tabs.Items.Add(new TabItem { Header = "Function plot", Content = PlotUI() });
        tabs.Items.Add(new TabItem { Header = "Drawing aids", Content = AidsUI() });
        root.Children.Add(tabs); Content = root;
        _family.SelectionChanged += (_, _) => RefreshUnits(); RefreshUnits();
    }
    private UIElement CalculatorUI()
    {
        var panel = new StackPanel { Margin = new Thickness(24) };
        panel.Children.Add(WorkbenchUI.Label("Calculate a value", 22));
        panel.Children.Add(WorkbenchUI.Label("Numbers, + − × ÷ ^, brackets, pi, e and x. Functions: sqrt, sin, cos, tan, asin, acos, atan, ln, log, abs, exp, floor, ceil, round. Angles use radians."));
        panel.Children.Add(_expression); panel.Children.Add(WorkbenchUI.Row(WorkbenchUI.Label("x ="), _xValue, WorkbenchUI.Button("Calculate", Calculate)));
        panel.Children.Add(_answer);
        var keypad = new WrapPanel { MaxWidth = 650 };
        foreach (var key in new[] { "7", "8", "9", "/", "sqrt(", "sin(", "4", "5", "6", "*", "(", ")", "1", "2", "3", "-", "^", "pi", "0", ".", "+", "x", "ln(", "cos(" }) keypad.Children.Add(WorkbenchUI.Button(key, () => { var i = _expression.CaretIndex; _expression.SelectedText = key; _expression.CaretIndex = i + key.Length; _expression.Focus(); }));
        panel.Children.Add(keypad);
        panel.Children.Add(WorkbenchUI.Row(WorkbenchUI.Button("Clear calculation", () => { _expression.Clear(); _answer.Text = ""; _lastCalculation = null; }), WorkbenchUI.Button("Insert result on board", InsertCalculation), WorkbenchUI.Button("Copy result", () => Copy(_lastCalculation))));
        _expression.KeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Enter) Calculate(); };
        return panel;
    }
    private void Calculate()
    {
        try
        {
            var x = ExpressionParser.Evaluate(_xValue.Text); var result = ExpressionParser.Evaluate(_expression.Text, x);
            _answer.Text = WorkbenchUI.Format(result); _lastCalculation = _expression.Text + " = " + _answer.Text; _status.Text = "Calculated locally. Angles use radians.";
        }
        catch (Exception error) { _answer.Text = error.Message; _lastCalculation = null; }
    }
    private void InsertCalculation()
    {
        Calculate(); if (_lastCalculation == null) return;
        try { RequireBoard(); var point = InsertPosition(); _session.AddText(_lastCalculation, point.X, point.Y); _status.Text = "Inserted calculation as editable board text."; }
        catch (Exception error) { _status.Text = error.Message; }
    }
    private UIElement UnitsUI()
    {
        var panel = new StackPanel { Margin = new Thickness(24) };
        panel.Children.Add(WorkbenchUI.Label("Convert compatible units", 22)); panel.Children.Add(WorkbenchUI.Row(WorkbenchUI.Label("Quantity"), _family));
        panel.Children.Add(WorkbenchUI.Row(_unitValue, _from, WorkbenchUI.Label("→", 24), _to, WorkbenchUI.Button("Convert", ConvertUnits))); panel.Children.Add(_converted);
        panel.Children.Add(WorkbenchUI.Row(WorkbenchUI.Button("Insert conversion on board", () => { ConvertUnits(); if (_lastConversion != null) { try { RequireBoard(); var p = InsertPosition(); _session.AddText(_lastConversion, p.X, p.Y); _status.Text = "Inserted conversion as editable text."; } catch (Exception error) { _status.Text = error.Message; } } }), WorkbenchUI.Button("Copy conversion", () => Copy(_lastConversion))));
        panel.Children.Add(WorkbenchUI.Label("The value can be a calculation such as 25/2. The selected quantity keeps incompatible dimensions separate."));
        return panel;
    }
    private void RefreshUnits()
    {
        if (_family.SelectedItem is not EngineeringUnitFamily family) return;
        _from.ItemsSource = family.Units.Keys; _to.ItemsSource = family.Units.Keys; _from.SelectedIndex = 0; _to.SelectedIndex = Math.Min(2, family.Units.Count - 1); _converted.Text = ""; _lastConversion = null;
    }
    private void ConvertUnits()
    {
        try
        {
            if (_family.SelectedItem is not EngineeringUnitFamily family || _from.SelectedItem is not string from || _to.SelectedItem is not string to) throw new FormatException("Choose the quantity and units.");
            var value = ExpressionParser.Evaluate(_unitValue.Text); var result = family.Convert(value, from, to); _converted.Text = WorkbenchUI.Format(result) + " " + to;
            _lastConversion = WorkbenchUI.Format(value) + " " + from + " = " + _converted.Text;
        }
        catch (Exception error) { _converted.Text = error.Message; _lastConversion = null; }
    }
    private UIElement PlotUI()
    {
        var dock = new DockPanel { Margin = new Thickness(22) };
        var controls = new StackPanel(); controls.Children.Add(WorkbenchUI.Label("Plot y = f(x)", 22)); controls.Children.Add(_function);
        controls.Children.Add(WorkbenchUI.Label("Use x, numbers, brackets and the calculator functions. Trigonometric functions use radians. Discontinuities split the curve."));
        controls.Children.Add(WorkbenchUI.Row(WorkbenchUI.Label("x min / max"), _xmin, _xmax, WorkbenchUI.Label("y min / max"), _ymin, _ymax));
        controls.Children.Add(WorkbenchUI.Row(WorkbenchUI.Button("Preview graph", PreviewPlot), WorkbenchUI.Button("Insert editable graph", InsertPlot)));
        DockPanel.SetDock(controls, Dock.Top); dock.Children.Add(controls); dock.Children.Add(_plotPreview); return dock;
    }
    private FunctionPlot ReadPlot()
    {
        var xmin = WorkbenchUI.Number(_xmin, "x minimum", -1e9, 1e9); var xmax = WorkbenchUI.Number(_xmax, "x maximum", -1e9, 1e9);
        var ymin = WorkbenchUI.Number(_ymin, "y minimum", -1e9, 1e9); var ymax = WorkbenchUI.Number(_ymax, "y maximum", -1e9, 1e9);
        if (xmax <= xmin || ymax <= ymin) throw new FormatException("Maximum values must be greater than minimum values.");
        if (xmax - xmin < 1e-12 || ymax - ymin < 1e-12) throw new FormatException("Choose an axis range wider than 0.000000000001.");
        var paths = new List<List<Point>>(); var current = new List<Point>();
        void Split() { if (current.Count > 1) paths.Add(current); current = []; }
        for (var i = 0; i <= 800; i++)
        {
            var x = xmin + (xmax - xmin) * i / 800;
            double y;
            try { y = ExpressionParser.Evaluate(_function.Text, x); }
            catch (FormatException error) when (error.Message.Contains("finite real", StringComparison.Ordinal) || error.Message.Contains("divide by zero", StringComparison.Ordinal)) { Split(); continue; }
            if (y < ymin || y > ymax) { Split(); continue; }
            if (current.Count > 0 && Math.Abs(y - current[^1].Y) > (ymax - ymin) * .4) Split();
            current.Add(new Point(x, y));
        }
        Split(); if (paths.Count == 0) throw new FormatException("No finite visible points in this range. Check the function and axis limits.");
        return new FunctionPlot(_function.Text, xmin, xmax, ymin, ymax, paths);
    }
    private void PreviewPlot()
    {
        try { _plot = ReadPlot(); _plotPreview.Plot = _plot; _status.Text = "Graph sampled at 801 x positions. Review its range before inserting."; }
        catch (Exception error) { _status.Text = error.Message; }
    }
    private void InsertPlot()
    {
        try
        {
            RequireBoard(); var plot = ReadPlot(); _plot = plot; _plotPreview.Plot = plot;
            var width = Math.Clamp(_session.Board.Width - 280, 300, 1100); var height = Math.Clamp(_session.Board.Height - 300, 220, 650);
            var origin = InsertPosition(); origin.X = Math.Clamp(origin.X, -999800, 999800 - width); origin.Y = Math.Clamp(origin.Y, -999800, 999800 - height);
            InkPoint Map(double x, double y) => new(origin.X + (x - plot.XMin) / (plot.XMax - plot.XMin) * width, origin.Y + (plot.YMax - y) / (plot.YMax - plot.YMin) * height);
            var additions = new List<DrawingElement> { new() { Kind = "rectangle", Points = [Map(plot.XMin, plot.YMax), Map(plot.XMax, plot.YMin)], Color = InkColor.Graphite, Width = 1 } };
            if (plot.XMin <= 0 && plot.XMax >= 0) additions.Add(new() { Kind = "arrow", Points = [Map(0, plot.YMin), Map(0, plot.YMax)], Color = InkColor.Graphite, Width = 2 });
            if (plot.YMin <= 0 && plot.YMax >= 0) additions.Add(new() { Kind = "arrow", Points = [Map(plot.XMin, 0), Map(plot.XMax, 0)], Color = InkColor.Graphite, Width = 2 });
            for (var i = 0; i <= 10; i++)
            {
                var x = plot.XMin + (plot.XMax - plot.XMin) * i / 10; var y = plot.YMin + (plot.YMax - plot.YMin) * i / 10; var px = Map(x, plot.YMin); var py = Map(plot.XMin, y);
                additions.Add(new() { Kind = "text", Points = [new InkPoint(px.X - 12, px.Y + 12)], Color = InkColor.Graphite, Text = x.ToString("G3", CultureInfo.InvariantCulture), FontSize = 17 });
                additions.Add(new() { Kind = "text", Points = [new InkPoint(py.X - 60, py.Y - 9)], Color = InkColor.Graphite, Text = y.ToString("G3", CultureInfo.InvariantCulture), FontSize = 17 });
            }
            foreach (var path in plot.Paths) additions.Add(new() { Kind = "stroke", Points = path.Select(p => Map(p.X, p.Y)).ToList(), Color = _session.Color, Width = 3, BrushSettings = new BrushSettings { MinWidth = 3, MaxWidth = 3, PressureEnabled = false } });
            additions.Add(new() { Kind = "text", Points = [new InkPoint(origin.X, origin.Y - 40)], Color = _session.Color, Text = "y = " + plot.Expression, FontSize = 26 });
            var proposed = BoardCodec.Clone(_session.Board); proposed.Elements.AddRange(additions); BoardCodec.Validate(proposed);
            _session.Checkpoint(); _session.Board.Elements.AddRange(additions); _session.SelectedIds.Clear(); foreach (var element in additions) _session.SelectedIds.Add(element.Id); _session.NotifyChanged();
            _status.Text = "Inserted editable axes, labels and curve strokes. Undo removes the whole graph.";
        }
        catch (Exception error) { _status.Text = error.Message; }
    }
    private UIElement AidsUI()
    {
        var panel = new StackPanel { Margin = new Thickness(24) };
        panel.Children.Add(WorkbenchUI.Label("Measure and construct on your board", 22));
        var ruler = new CheckBox { Content = "Show ruler", IsChecked = _session.ShowRuler, Margin = new Thickness(5, 12, 5, 12) };
        var protractor = new CheckBox { Content = "Show protractor", IsChecked = _session.ShowProtractor, Margin = new Thickness(5, 12, 5, 12) };
        ruler.Checked += (_, _) => { _session.ShowRuler = true; _session.NotifyViewChanged(); }; ruler.Unchecked += (_, _) => { _session.ShowRuler = false; _session.NotifyViewChanged(); };
        protractor.Checked += (_, _) => { _session.ShowProtractor = true; _session.NotifyViewChanged(); }; protractor.Unchecked += (_, _) => { _session.ShowProtractor = false; _session.NotifyViewChanged(); };
        panel.Children.Add(ruler); panel.Children.Add(protractor);
        var length = WorkbenchUI.Field(WorkbenchUI.Format(_session.FixedLineLengthMM), 120); panel.Children.Add(WorkbenchUI.Row(WorkbenchUI.Label("Fixed line length · mm"), length));
        panel.Children.Add(WorkbenchUI.Label("Zero allows a free line. The board scale converts millimetres into drawing points."));
        panel.Children.Add(WorkbenchUI.Button("Apply and use line tool", () => { try { _session.FixedLineLengthMM = WorkbenchUI.Number(length, "Fixed line length", 0, 100000); _session.Tool = "Line"; _session.NotifyViewChanged(); _status.Text = "Line tool ready. Draw on the board using the ruler or protractor."; } catch (Exception error) { _status.Text = error.Message; } }));
        return panel;
    }
    private void RequireBoard() { if (_session.Board.Id != _boardId) throw new InvalidOperationException("The board changed while this tools window was open. Reopen tools from the intended board."); if (_session.Board.Elements.Count >= 100000) throw new InvalidOperationException("The board object limit was reached. Use a new board."); }
    private Point InsertPosition()
    {
        if (!double.IsFinite(_session.Offset.X) || !double.IsFinite(_session.Offset.Y) || !double.IsFinite(_session.Zoom)) throw new InvalidOperationException("The board view has invalid coordinates.");
        var zoom = Math.Clamp(_session.Zoom, .02, 40);
        return new Point(Math.Clamp((140 - _session.Offset.X) / zoom, -999800, 999000), Math.Clamp((180 - _session.Offset.Y) / zoom, -999800, 999000));
    }
    private void Copy(string? value) { if (value == null) { _status.Text = "Calculate a result first."; return; } try { Clipboard.SetText(value); _status.Text = "Result copied."; } catch (Exception error) { _status.Text = error.Message; } }
}

internal sealed class FunctionPlotPreview : FrameworkElement
{
    private FunctionPlot? _plot;
    public FunctionPlot? Plot { get => _plot; set { _plot = value; InvalidateVisual(); } }
    protected override void OnRender(DrawingContext context)
    {
        base.OnRender(context); context.DrawRectangle(Brushes.White, new Pen(Brushes.LightGray, 1), new Rect(RenderSize));
        if (_plot == null) { DrawText(context, "Preview your function here", new Point(30, 30), 18); return; }
        var plot = _plot; var width = Math.Max(1, ActualWidth - 90); var height = Math.Max(1, ActualHeight - 65);
        Point Map(double x, double y) => new(65 + (x - plot.XMin) / (plot.XMax - plot.XMin) * width, 20 + (plot.YMax - y) / (plot.YMax - plot.YMin) * height);
        for (var i = 0; i <= 10; i++)
        {
            var x = plot.XMin + (plot.XMax - plot.XMin) * i / 10; var y = plot.YMin + (plot.YMax - plot.YMin) * i / 10;
            context.DrawLine(new Pen(Brushes.Gainsboro, .5), Map(x, plot.YMin), Map(x, plot.YMax)); context.DrawLine(new Pen(Brushes.Gainsboro, .5), Map(plot.XMin, y), Map(plot.XMax, y));
            var px = Map(x, plot.YMin); var py = Map(plot.XMin, y); DrawText(context, x.ToString("G3", CultureInfo.InvariantCulture), new Point(px.X - 10, px.Y + 8), 11); DrawText(context, y.ToString("G3", CultureInfo.InvariantCulture), new Point(5, py.Y - 7), 11);
        }
        if (plot.XMin <= 0 && plot.XMax >= 0) context.DrawLine(new Pen(Brushes.Gray, 1.5), Map(0, plot.YMin), Map(0, plot.YMax));
        if (plot.YMin <= 0 && plot.YMax >= 0) context.DrawLine(new Pen(Brushes.Gray, 1.5), Map(plot.XMin, 0), Map(plot.XMax, 0));
        foreach (var path in plot.Paths)
        {
            var geometry = new StreamGeometry(); using (var sink = geometry.Open()) { sink.BeginFigure(Map(path[0].X, path[0].Y), false, false); sink.PolyLineTo(path.Skip(1).Select(p => Map(p.X, p.Y)).ToArray(), true, false); }
            context.DrawGeometry(null, new Pen(Brushes.RoyalBlue, 2), geometry);
        }
    }
    private static void DrawText(DrawingContext context, string value, Point point, double size) => context.DrawText(new FormattedText(value, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, new Typeface("Segoe UI"), size, Brushes.DimGray, 1), point);
}

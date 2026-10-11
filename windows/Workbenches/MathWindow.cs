using System.Windows;
using System.Windows.Controls;
using System.Windows.Ink;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

namespace KarimEldamatyWindows;

public sealed class MathWindow : Window
{
    private readonly DrawingSession _session;
    private readonly Guid? _sourceId;
    private readonly Guid _boardId;
    private readonly InkCanvas _pad = new() { Background = Brushes.White, MinHeight = 300, MinWidth = 350, EditingMode = InkCanvasEditingMode.Ink, DefaultDrawingAttributes = new DrawingAttributes { Color = Colors.Black, Width = 5, Height = 5, IgnorePressure = false, FitToCurve = false } };
    private readonly ListBox _matches = new() { MinHeight = 240 };
    private readonly ListBox _catalog = new() { MinHeight = 240 };
    private readonly TextBox _search = WorkbenchUI.Field("", 210);
    private readonly TextBox _formula = new() { AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, Height = 110, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, FontFamily = new FontFamily("Consolas"), FontSize = 16, Padding = new Thickness(12), MaxLength = 4096 };
    private readonly NativeMathRenderer _preview = new() { Height = 170, HorizontalAlignment = HorizontalAlignment.Stretch };
    private readonly TextBlock _validation = WorkbenchUI.Label("Enter a formula, or send a recognised symbol to the editor.");
    private readonly TextBlock _status = WorkbenchUI.Label("Draw one handwritten symbol, then recognise it offline.");
    private readonly TextBlock _catalogCount = WorkbenchUI.Label("");
    private readonly TabControl _tabs = new();
    private readonly TabControl _resultTabs = new();
    private readonly Button _recognise;
    private readonly Button _insertSymbol;
    private readonly Button _insertFormula;
    private readonly DispatcherTimer _searchTimer = new() { Interval = TimeSpan.FromMilliseconds(160) };
    private CancellationTokenSource? _recognition;
    private bool _closed;

    public MathWindow(DrawingSession session)
    {
        _session = session; _boardId = session.Board.Id;
        WorkbenchUI.Window(this, "Maths · DeTeXt · SketchGlide", 1080, 780);
        _recognise = WorkbenchUI.Button("Recognise offline", () => _ = RecogniseAsync());
        _insertSymbol = WorkbenchUI.Button("Insert symbol", InsertSelectedSymbol);
        _insertFormula = WorkbenchUI.Button("Insert editable formula", () => InsertFormula(false));
        var existing = session.Board.Elements.FirstOrDefault(e => session.SelectedIds.Count == 1 && session.SelectedIds.Contains(e.Id) && e.Kind == "symbol" && e.Text.StartsWith("mathlatex:", StringComparison.Ordinal));
        if (existing != null) { _sourceId = existing.Id; _formula.Text = existing.Text[10..]; _insertFormula.Content = "Update selected formula"; }
        WorkbenchUI.ThemeList(_matches); WorkbenchUI.ThemeList(_catalog);
        BuildUI(); RefreshFormula();
        Closed += (_, _) => { _closed = true; _recognition?.Cancel(); _searchTimer.Stop(); };
        _formula.TextChanged += (_, _) => RefreshFormula();
        _pad.PreviewTouchDown += (_, e) => e.Handled = true;
        _pad.StrokeCollected += (_, _) => PadChanged();
        _pad.StrokeErased += (_, _) => PadChanged();
        _matches.SelectionChanged += (_, _) => RefreshSymbolActions(); _catalog.SelectionChanged += (_, _) => RefreshSymbolActions(); _resultTabs.SelectionChanged += (_, _) => RefreshSymbolActions();
        _search.TextChanged += (_, _) => { _searchTimer.Stop(); _searchTimer.Start(); };
        _searchTimer.Tick += (_, _) => { _searchTimer.Stop(); RefreshCatalog(); };
        RefreshCatalog();
    }
    private void BuildUI()
    {
        var root = new DockPanel { Margin = new Thickness(18) };
        var heading = WorkbenchUI.Label("Handwritten symbols and editable formulas", 24); DockPanel.SetDock(heading, Dock.Top); root.Children.Add(heading);
        DockPanel.SetDock(_status, Dock.Bottom); root.Children.Add(_status);
        var recognition = new Grid(); recognition.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1.15, GridUnitType.Star) }); recognition.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var padArea = new DockPanel();
        var penButtons = new WrapPanel();
        foreach (var item in new UIElement[] { _recognise, WorkbenchUI.Button("Cancel", () => _recognition?.Cancel()), WorkbenchUI.Button("Use selected ink", UseSelectedInk), WorkbenchUI.Button("Clear pad", () => { _recognition?.Cancel(); _pad.Strokes.Clear(); _matches.ItemsSource = null; _status.Text = "Draw one symbol, then recognise it."; }), WorkbenchUI.Button("Undo stroke", () => { if (_pad.Strokes.Count > 0) { _pad.Strokes.RemoveAt(_pad.Strokes.Count - 1); PadChanged(); } }), WorkbenchUI.Button("Pen", () => _pad.EditingMode = InkCanvasEditingMode.Ink), WorkbenchUI.Button("Eraser", () => _pad.EditingMode = InkCanvasEditingMode.EraseByStroke) }) penButtons.Children.Add(item);
        DockPanel.SetDock(penButtons, Dock.Bottom); padArea.Children.Add(penButtons);
        var instruction = WorkbenchUI.Label("Draw one symbol using your pen or mouse. Scores rank suggestions; review the match before inserting."); DockPanel.SetDock(instruction, Dock.Top); padArea.Children.Add(instruction);
        padArea.Children.Add(new Border { Child = _pad, BorderBrush = Brushes.LightGray, BorderThickness = new Thickness(1), Margin = new Thickness(3), ClipToBounds = true });
        var padCard = WorkbenchUI.Card(padArea); Grid.SetColumn(padCard, 0); recognition.Children.Add(padCard);
        var resultArea = new DockPanel();
        var symbolButtons = new WrapPanel();
        foreach (var item in new UIElement[] { _insertSymbol, WorkbenchUI.Button("Send to formula", SendToFormula), WorkbenchUI.Button("Copy LaTeX", CopySymbol) }) symbolButtons.Children.Add(item);
        DockPanel.SetDock(symbolButtons, Dock.Bottom); resultArea.Children.Add(symbolButtons);
        _resultTabs.Items.Add(new TabItem { Header = "Recognition matches", Content = _matches });
        var catalogPanel = new DockPanel();
        var libraryHeader = new StackPanel(); libraryHeader.Children.Add(WorkbenchUI.Label("Search public LaTeX commands")); libraryHeader.Children.Add(_search); libraryHeader.Children.Add(_catalogCount);
        DockPanel.SetDock(libraryHeader, Dock.Top); catalogPanel.Children.Add(libraryHeader); catalogPanel.Children.Add(_catalog);
        _resultTabs.Items.Add(new TabItem { Header = "Command library", Content = catalogPanel }); resultArea.Children.Add(_resultTabs);
        var resultCard = WorkbenchUI.Card(resultArea); Grid.SetColumn(resultCard, 1); recognition.Children.Add(resultCard);
        _tabs.Items.Add(new TabItem { Header = "Recognise a symbol", Content = recognition });
        var editor = new StackPanel { Margin = new Thickness(20) };
        editor.Children.Add(WorkbenchUI.Label("Type LaTeX, use an example, or send a recognised symbol here. Fractions, roots, powers, subscripts and common Greek letters render locally."));
        var examples = new WrapPanel();
        foreach (var (name, latex) in new[] { ("Stress", @"\sigma = \frac{F}{A}"), ("Ohm's law", "V = I R"), ("Kinetic energy", @"E_k = \frac{1}{2} m v^2"), ("Quadratic", @"x = \frac{-b \pm \sqrt{b^2 - 4 a c}}{2 a}") }) examples.Children.Add(WorkbenchUI.Button(name, () => _formula.Text = latex));
        examples.Children.Add(WorkbenchUI.Button("Clear formula", () => _formula.Clear())); editor.Children.Add(examples);
        editor.Children.Add(_formula);
        var notation = new WrapPanel();
        foreach (var (name, latex) in new[] { ("Fraction", @"\frac{a}{b}"), ("Root", @"\sqrt{x}"), ("Power", "x^{2}"), ("Subscript", "x_{1}"), ("π", @"\pi"), ("θ", @"\theta"), ("σ", @"\sigma"), ("Δ", @"\Delta"), ("±", @"\pm"), ("∫", @"\int"), ("∑", @"\sum") }) notation.Children.Add(WorkbenchUI.Button(name, () => AppendFormula(latex)));
        editor.Children.Add(notation); editor.Children.Add(WorkbenchUI.Label("Preview", 18)); editor.Children.Add(_preview); editor.Children.Add(_validation);
        var actions = new WrapPanel(); actions.Children.Add(WorkbenchUI.Button("Copy LaTeX", () => Copy(_formula.Text))); actions.Children.Add(_insertFormula);
        if (_sourceId != null) actions.Children.Add(WorkbenchUI.Button("Insert a copy", () => InsertFormula(true)));
        editor.Children.Add(actions); _tabs.Items.Add(new TabItem { Header = "Formula editor", Content = new ScrollViewer { Content = editor, VerticalScrollBarVisibility = ScrollBarVisibility.Auto } });
        if (_sourceId != null) _tabs.SelectedIndex = 1;
        root.Children.Add(_tabs); Content = root;
    }
    private void RefreshFormula()
    {
        _preview.Latex = _formula.Text;
        var valid = FormulaRenderer.TryValidate(_formula.Text, out var error);
        _validation.Text = valid ? "Editable formula ready to insert. Its LaTeX source stays in the board file." : error;
        _insertFormula.IsEnabled = valid;
    }
    private void RefreshCatalog()
    {
        try
        {
            var found = MathSymbolCatalog.Search(_search.Text.Trim()); _catalog.ItemsSource = found;
            _catalogCount.Text = $"{found.Count:n0} of {MathSymbolCatalog.All.Count:n0} commands. Commands needing extra TeX packages can be copied.";
        }
        catch (Exception error) { _catalogCount.Text = error.Message; }
        RefreshSymbolActions();
    }
    private string? SelectedCommand => _resultTabs.SelectedIndex == 1 ? (_catalog.SelectedItem as MathSymbolDefinition)?.Command : (_matches.SelectedItem as MathSymbolCandidate)?.Command;
    private void RefreshSymbolActions()
    {
        var command = SelectedCommand;
        _insertSymbol.IsEnabled = !string.IsNullOrEmpty(command) && (MathSymbolCatalog.ToUnicode(command) != null || FormulaRenderer.TryValidate(command, out _));
    }
    private void PadChanged()
    {
        _recognition?.Cancel(); _matches.ItemsSource = null;
        _status.Text = "Symbol pad changed. Choose Recognise offline for the current ink.";
    }
    private async Task RecogniseAsync()
    {
        if (_recognition != null) return;
        var strokes = _pad.Strokes.Select(s => s.StylusPoints.Select(p => new InkPoint(p.X, p.Y, p.PressureFactor)).ToArray()).ToList();
        var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(45)); _recognition = cancellation;
        _recognise.IsEnabled = false; _status.Text = "Finding offline symbol matches…";
        try
        {
            var candidates = await MathRecognitionService.Shared.RecognizeAsync(strokes, cancellation.Token);
            if (_closed || cancellation.IsCancellationRequested) return;
            _matches.ItemsSource = candidates; _resultTabs.SelectedIndex = 0;
            _status.Text = $"{candidates.Count} suggestions. Select the symbol you meant. Your board ink was preserved.";
        }
        catch (OperationCanceledException) { if (!_closed) _status.Text = "Recognition cancelled. The symbol pad was kept."; }
        catch (Exception error) { if (!_closed) _status.Text = error.Message; }
        finally { if (!_closed) _recognise.IsEnabled = true; _recognition = null; cancellation.Dispose(); }
    }
    private void UseSelectedInk()
    {
        var selected = _session.Board.Elements.Where(e => _session.SelectedIds.Contains(e.Id) && e.Kind == "stroke" && e.Points.Count > 0).ToList();
        if (selected.Count == 0) { _status.Text = "Select handwritten strokes on the board first."; return; }
        if (selected.Count > 2048 || selected.Sum(s => (long)s.Points.Count) > 100000) { _status.Text = "Select one symbol with at most 2,048 strokes and 100,000 points."; return; }
        var points = selected.SelectMany(e => e.Points).ToArray();
        var minX = points.Min(p => p.X); var minY = points.Min(p => p.Y); var spanX = points.Max(p => p.X) - minX; var spanY = points.Max(p => p.Y) - minY;
        var width = Math.Max(300, _pad.ActualWidth); var height = Math.Max(250, _pad.ActualHeight); var scale = Math.Min((width - 70) / Math.Max(1, spanX), (height - 70) / Math.Max(1, spanY));
        var ox = (width - spanX * scale) / 2; var oy = (height - spanY * scale) / 2;
        var copied = new StrokeCollection();
        foreach (var stroke in selected)
        {
            var stylus = new StylusPointCollection(stroke.Points.Select(p => new StylusPoint((p.X - minX) * scale + ox, (p.Y - minY) * scale + oy, (float)Math.Clamp(p.Pressure, 0, 1))));
            copied.Add(new Stroke(stylus) { DrawingAttributes = _pad.DefaultDrawingAttributes.Clone() });
        }
        _recognition?.Cancel(); _pad.Strokes = copied; _matches.ItemsSource = null; _status.Text = "Selected ink copied into the pad. Choose Recognise offline.";
    }
    private void SendToFormula()
    {
        if (SelectedCommand is not string command) { _status.Text = "Select a command first."; return; }
        AppendFormula(command); _tabs.SelectedIndex = 1;
    }
    private void AppendFormula(string latex)
    {
        var position = _formula.CaretIndex; var prefix = position > 0 && !char.IsWhiteSpace(_formula.Text[position - 1]) ? " " : ""; var suffix = position < _formula.Text.Length && !char.IsWhiteSpace(_formula.Text[position]) ? " " : "";
        var insertion = prefix + latex + suffix;
        if (_formula.Text.Length - _formula.SelectionLength + insertion.Length > 4096) { _status.Text = "The formula limit is 4,096 characters. Your existing source was kept."; return; }
        _formula.SelectedText = insertion; _formula.CaretIndex = position + insertion.Length; _formula.SelectionLength = 0; _formula.Focus();
    }
    private void Copy(string text)
    {
        if (string.IsNullOrEmpty(text)) { _status.Text = "Choose a command or enter a formula first."; return; }
        try { Clipboard.SetText(text); _status.Text = "LaTeX copied."; } catch (Exception error) { _status.Text = "Clipboard is unavailable: " + error.Message; }
    }
    private void CopySymbol() { if (SelectedCommand is string command) Copy(command); else _status.Text = "Select a command first."; }
    private void InsertSelectedSymbol()
    {
        if (SelectedCommand is not string command) return;
        try
        {
            RequireBoard();
            var unicode = MathSymbolCatalog.ToUnicode(command);
            if (unicode != null)
            {
                if (_session.Board.Elements.Count >= 100000) throw new InvalidOperationException("The board object limit was reached. Use a new board for this symbol.");
                var p = InsertPosition(); _session.AddText(unicode, p.X, p.Y, 36); _status.Text = "Inserted editable symbol. Your ink was preserved.";
            }
            else if (FormulaRenderer.TryValidate(command, out _)) InsertFormulaSource(command, true);
        }
        catch (Exception error) { _status.Text = error.Message; }
    }
    private Point InsertPosition()
    {
        if (!double.IsFinite(_session.Zoom) || !double.IsFinite(_session.Offset.X) || !double.IsFinite(_session.Offset.Y)) throw new InvalidOperationException("The board view has invalid coordinates. Reopen this workbench.");
        var zoom = Math.Clamp(_session.Zoom, .02, 40);
        return new Point(Math.Clamp((120 - _session.Offset.X) / zoom, -999000, 999000), Math.Clamp((120 - _session.Offset.Y) / zoom, -999000, 999000));
    }
    private void RequireBoard()
    {
        if (_session.Board.Id != _boardId) throw new InvalidOperationException("The board changed while this maths window was open. Copy the LaTeX and reopen Maths from the intended board.");
    }
    private void InsertFormula(bool copy) => InsertFormulaSource(_formula.Text, copy);
    private void InsertFormulaSource(string latex, bool copy)
    {
        try
        {
            RequireBoard();
            if (!FormulaRenderer.TryValidate(latex, out var error)) throw new FormatException(error);
            var position = InsertPosition(); var zoom = Math.Clamp(_session.Zoom, .02, 40); var layout = FormulaRenderer.Layout(latex, _session.Color, 36);
            var w = Math.Clamp(layout.Width + 32, 80, 1800) / zoom; var h = Math.Clamp(layout.Height + 32, 55, 1000) / zoom;
            var selected = copy ? null : _session.Board.Elements.FirstOrDefault(e => e.Id == _sourceId && e.Kind == "symbol" && !e.Locked);
            if (selected == null && _session.Board.Elements.Count >= 100000) throw new InvalidOperationException("The board object limit was reached. Use a new board for this formula.");
            _session.Checkpoint();
            if (selected != null) { selected.Text = "mathlatex:" + latex; }
            else
            {
                selected = new DrawingElement { Kind = "symbol", Text = "mathlatex:" + latex, Color = _session.Color, FontSize = 36, Points = [new InkPoint(position.X, position.Y), new InkPoint(position.X + w, position.Y + h)] };
                _session.Board.Elements.Add(selected);
            }
            _session.SelectedIds.Clear(); _session.SelectedIds.Add(selected.Id); _session.NotifyChanged();
            _status.Text = "Saved editable maths on your board. Reopen Maths with the formula selected to edit its source.";
        }
        catch (Exception error) { _status.Text = error.Message; }
    }
}

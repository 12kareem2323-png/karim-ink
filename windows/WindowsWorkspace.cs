using System.Text.Json;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using Microsoft.Win32;

namespace KarimEldamatyWindows;

public sealed partial class MainWindow
{
    private readonly PdfBook pdfBook;
    private Button? pdfButton;
    private bool pdfBusy;

    private void BuildEditor()
    {
        editor.RowDefinitions.Add(new() { Height = GridLength.Auto });
        editor.RowDefinitions.Add(new() { Height = new GridLength(1, GridUnitType.Star) });
        editor.RowDefinitions.Add(new() { Height = GridLength.Auto });
        var header = new Grid();
        header.ColumnDefinitions.Add(new() { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new() { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new() { Width = GridLength.Auto });
        header.Children.Add(UI.Button("‹ Library", () => _ = HomeAsync()));
        title.Background = Brushes.Transparent;
        title.BorderThickness = new Thickness(0);
        title.FontSize = 17;
        title.FontWeight = FontWeights.SemiBold;
        title.VerticalContentAlignment = VerticalAlignment.Center;
        title.ToolTip = "Drawing title";
        title.LostKeyboardFocus += (_, _) => SaveTitle();
        Grid.SetColumn(title, 1);
        header.Children.Add(title);

        var actions = new WrapPanel { VerticalAlignment = VerticalAlignment.Center, MaxWidth = 485 };
        actions.Children.Add(MenuButton("Paper", menu => BuildPaperMenu(menu)));
        pdfButton = MenuButton("PDF", BuildPdfMenu);
        actions.Children.Add(pdfButton);
        actions.Children.Add(UI.Button("Guides", () => TogglePanel("Tools")));
        actions.Children.Add(UI.Button("Symbols", () => TogglePanel("Symbols")));
        actions.Children.Add(UI.Button("AI", () => TogglePanel("AI")));
        actions.Children.Add(UI.Button("Export", ShowExportMenu));
        actions.Children.Add(MenuButton("More", menu =>
        {
            UI.Menu(menu, "Maths & DeTeXt", () => ShowWindow(new MathWindow(Session)));
            UI.Menu(menu, "3D sketches", () => ShowWindow(new Sketch3DWindow(Session)));
            UI.Menu(menu, "Calculator & graphs", () => ShowWindow(new EngineeringWindow(Session)));
            UI.Menu(menu, "Notes", () => TogglePanel("Notes"));
            UI.Menu(menu, "Switch light / dark", WindowsTheme.Toggle);
            UI.Menu(menu, "Check for updates…", () => ShowWindow(new WindowsUpdatesWindow()));
        }));
        Grid.SetColumn(actions, 2);
        header.Children.Add(actions);
        var headerGlass = UI.Card(header, 5);
        headerGlass.Margin = new Thickness(12, 9, 12, 9);
        editor.Children.Add(headerGlass);

        var workspace = new Grid { Margin = new Thickness(12, 0, 12, 0) };
        workspace.ColumnDefinitions.Add(new() { Width = new GridLength(1, GridUnitType.Star) });
        workspace.ColumnDefinitions.Add(new() { Width = GridLength.Auto });
        Grid.SetRow(workspace, 1);
        editor.Children.Add(workspace);
        var canvasCard = UI.Card(canvasHost, 0);
        canvasCard.CornerRadius = new CornerRadius(18);
        canvasCard.ClipToBounds = true;
        workspace.Children.Add(canvasCard);
        canvasHost.Children.Add(Canvas);
        canvasHost.Children.Add(BuildDrawingDock());

        inspector.Width = 316;
        inspector.Margin = new Thickness(9, 0, 0, 0);
        inspector.CornerRadius = new CornerRadius(18);
        inspector.SetResourceReference(Border.BackgroundProperty, "CardBrush");
        inspector.SetResourceReference(Border.BorderBrushProperty, "BorderBrush");
        inspector.BorderThickness = new Thickness(.6);
        inspector.Visibility = Visibility.Collapsed;
        inspector.Child = inspectorContent;
        Grid.SetColumn(inspector, 1);
        workspace.Children.Add(inspector);

        var footer = new DockPanel { Margin = new Thickness(22, 7, 22, 9) };
        diagnostics.HorizontalAlignment = HorizontalAlignment.Right;
        DockPanel.SetDock(diagnostics, Dock.Right);
        footer.Children.Add(diagnostics);
        status.FontSize = 11;
        status.TextTrimming = TextTrimming.CharacterEllipsis;
        footer.Children.Add(status);
        Grid.SetRow(footer, 2);
        editor.Children.Add(footer);
        SetTool("Draw");
    }

    private Border BuildDrawingDock()
    {
        var row = new WrapPanel { HorizontalAlignment = HorizontalAlignment.Center };
        void Tool(string name, string label)
        {
            var button = UI.Button(label, () => SetTool(name));
            AutomationProperties.SetName(button, name);
            button.ToolTip = name;
            toolButtons[name] = button;
            row.Children.Add(button);
        }
        Tool("Draw", "✎ Draw");
        Tool("Eraser", "Erase");
        Tool("Select", "Select");
        Tool("Lasso", "Lasso");
        pens.ItemsSource = BrushSettings.PenNames;
        pens.SelectedItem = Session.Pen;
        pens.Width = 139;
        AutomationProperties.SetName(pens, "Pen");
        pens.SelectionChanged += (_, _) =>
        {
            if (constructing || pens.SelectedItem is not string value) return;
            Canvas.FinishStroke();
            profiles.SaveProfile(Session, activeDevice);
            Session.SetPen(value);
            profiles.LoadProfile(Session, activeDevice);
            if (panel == "Tools") { toolsPanel = null; ShowPanel("Tools"); }
        };
        row.Children.Add(pens);
        row.Children.Add(UI.Button("Colour", () => EditInkColour()));
        row.Children.Add(MenuButton("Shapes", menu =>
        {
            foreach (var name in new[] { "Line", "Rectangle", "Ellipse", "Triangle", "Arrow", "Dimension" })
                UI.Menu(menu, name, () => SetTool(name));
        }));
        Tool("Text", "Text");
        row.Children.Add(MenuButton("Ink assist", menu =>
        {
            AddShapeMenu(menu);
            UI.Menu(menu, "Smooth selected ink", SmoothSelectedInk);
        }));

        var view = new StackPanel { Orientation = Orientation.Horizontal };
        Button Icon(string label, string name, Action action)
        {
            var button = UI.Button(label, action);
            AutomationProperties.SetName(button, name);
            button.ToolTip = name;
            return button;
        }
        view.Children.Add(Icon("↶", "Undo", () => { Canvas.FinishStroke(); Session.Undo(); }));
        view.Children.Add(Icon("↷", "Redo", () => { Canvas.FinishStroke(); Session.Redo(); }));
        view.Children.Add(Icon("−", "Zoom out", () => Zoom(.8)));
        view.Children.Add(UI.Button("Fit", Canvas.FitBoard));
        view.Children.Add(Icon("+", "Zoom in", () => Zoom(1.25)));
        row.Children.Add(view);
        var bar = UI.Card(row, 6);
        bar.HorizontalAlignment = HorizontalAlignment.Center;
        bar.VerticalAlignment = VerticalAlignment.Bottom;
        bar.MaxWidth = 1040;
        bar.Margin = new Thickness(10, 0, 10, 12);
        return bar;
    }

    private static Button MenuButton(string label, Action<ContextMenu> populate)
    {
        var button = new Button { Content = label };
        button.Click += (_, _) =>
        {
            var menu = new ContextMenu { PlacementTarget = button, Placement = PlacementMode.Bottom };
            populate(menu);
            menu.IsOpen = true;
        };
        return button;
    }

    private void EditInkColour()
    {
        Canvas.FinishStroke();
        if (NativeColorPicker.Pick(this, Session.Color) is { } color) SetColor(color);
    }

    private void SetPaper(string name)
    {
        if (name == Session.Board.Background) return;
        Canvas.FinishStroke();
        Session.Checkpoint();
        Session.Board.Background = name;
        Session.NotifyChanged();
        if (panel == "Tools") { toolsPanel = null; ShowPanel("Tools"); }
    }

    private ComboBox PaperPicker()
    {
        var picker = new ComboBox { ItemsSource = Board.BackgroundNames, SelectedItem = Session.Board.Background };
        AutomationProperties.SetName(picker, "Paper pattern");
        picker.SelectionChanged += (_, _) => { if (picker.SelectedItem is string name) SetPaper(name); };
        return picker;
    }

    private void BuildPaperMenu(ContextMenu menu)
    {
        foreach (var name in Board.BackgroundNames)
        {
            var item = new MenuItem { Header = name, IsCheckable = true, IsChecked = name == Session.Board.Background };
            item.Click += (_, _) => SetPaper(name);
            menu.Items.Add(item);
        }
    }

    private static readonly (InkShapeMode Mode, string Label)[] SnapOptions =
        [(InkShapeMode.Hold, "Hold to snap"), (InkShapeMode.OnRelease, "Snap on release"), (InkShapeMode.Off, "Shape snapping off")];

    private void AddShapeMenu(ContextMenu menu)
    {
        foreach (var (mode, label) in SnapOptions)
        {
            var item = new MenuItem { Header = label, IsCheckable = true, IsChecked = Session.ShapeMode == mode };
            item.Click += (_, _) => ChangeInkAssist(mode, Session.LearnedInkSmoothing);
            menu.Items.Add(item);
        }
        menu.Items.Add(new Separator());
        var smoothing = new MenuItem { Header = "Local ink smoothing", IsCheckable = true, IsChecked = Session.LearnedInkSmoothing };
        smoothing.Click += (_, _) => ChangeInkAssist(Session.ShapeMode, smoothing.IsChecked);
        menu.Items.Add(smoothing);
    }

    private void AddInkAssistControls(Panel panel)
    {
        var modes = new ComboBox
        {
            ItemsSource = SnapOptions.Select(option => option.Label),
            SelectedIndex = Array.FindIndex(SnapOptions, option => option.Mode == Session.ShapeMode)
        };
        AutomationProperties.SetName(modes, "Shape snapping");
        modes.SelectionChanged += (_, _) =>
        {
            if (modes.SelectedIndex >= 0)
                ChangeInkAssist(SnapOptions[modes.SelectedIndex].Mode, Session.LearnedInkSmoothing);
        };
        panel.Children.Add(modes);
        UI.Check(panel, "Local ink smoothing", Session.LearnedInkSmoothing,
            enabled => ChangeInkAssist(Session.ShapeMode, enabled));
        panel.Children.Add(UI.Button("Smooth selected ink", SmoothSelectedInk));
    }

    private record InkAssistSettings(InkShapeMode Mode, bool LocalSmoothing);
    private static string InkSettingsPath => Path.Combine(
        App.TestDataDirectory ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "KarimEldamaty"),
        "ink-assist.json");

    private void LoadInkAssist()
    {
        try
        {
            var file = new FileInfo(InkSettingsPath);
            if (file.Exists && file.Length < 4096 &&
                JsonSerializer.Deserialize<InkAssistSettings>(File.ReadAllText(file.FullName)) is { } settings &&
                Enum.IsDefined(settings.Mode))
            {
                Session.ShapeMode = settings.Mode;
                Session.LearnedInkSmoothing = settings.LocalSmoothing;
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException) { }
    }

    private void ChangeInkAssist(InkShapeMode mode, bool smoothing)
    {
        Canvas.FinishStroke();
        Session.ShapeMode = mode;
        Session.LearnedInkSmoothing = smoothing;
        var path = InkSettingsPath;
        var pending = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(pending, JsonSerializer.Serialize(new InkAssistSettings(mode, smoothing)));
            File.Move(pending, path, overwrite: true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            SetStatus("Ink assist settings could not be saved.");
        }
        finally { if (File.Exists(pending)) File.Delete(pending); }
    }

    private void SmoothSelectedInk()
    {
        Canvas.FinishStroke();
        var strokes = Session.Board.Elements.Where(e => Session.SelectedIds.Contains(e.Id) &&
            e.Kind == "stroke" && !e.Locked && e.Points.Count is >= 5 and <= InkDenoiseModel.MaximumSamples).ToArray();
        if (strokes.Length == 0) { SetStatus("Select a freehand stroke to smooth it."); return; }
        Session.Checkpoint();
        foreach (var stroke in strokes)
        {
            var positions = InkDenoiseModel.Refine(stroke.Points.Select(p => p.Point).ToArray(),
                Math.Max(.35, Session.Smoothing), Session.Zoom);
            for (var index = 0; index < positions.Length; index++)
            {
                stroke.Points[index].X = positions[index].X;
                stroke.Points[index].Y = positions[index].Y;
            }
        }
        Session.NotifyChanged();
        SetStatus("Ink smoothed on this PC · Ctrl+Z restores the original");
    }

    private void UpdatePdfControls()
    {
        if (pdfButton is not null)
            pdfButton.Content = PdfSheet.Read(Session.Board) is { } sheet ? $"PDF {sheet.Number}/{sheet.Count}" : "PDF";
    }

    private void BuildPdfMenu(ContextMenu menu)
    {
        UI.Menu(menu, "Open PDF…", () => _ = ChoosePdfAsync());
        if (PdfSheet.Read(Session.Board) is not { } sheet) return;
        menu.Items.Add(new Separator());
        UI.Menu(menu, "Page thumbnails…", () => _ = BrowsePdfAsync());
        UI.Menu(menu, "Find source text…   Ctrl+F", () => _ = BrowsePdfAsync(find: true));
        if (sheet.Number > 1) UI.Menu(menu, "Previous page", () => _ = NavigatePdfAsync(sheet, sheet.Number - 1));
        if (sheet.Number < sheet.Count) UI.Menu(menu, "Next page", () => _ = NavigatePdfAsync(sheet, sheet.Number + 1));
        menu.Items.Add(new Separator());
        UI.Menu(menu, "Export current page…", () => _ = ExportPdfBookAsync([sheet.Number]));
        UI.Menu(menu, "Export page range…", () => _ = ExportPdfBookAsync());
        UI.Menu(menu, "Export all pages…", () => _ = ExportPdfBookAsync(Enumerable.Range(1, sheet.Count).ToArray()));
    }

    private async Task ChoosePdfAsync()
    {
        var picker = new OpenFileDialog { Filter = "PDF document|*.pdf" };
        if (picker.ShowDialog(this) == true) await OpenArgumentAsync(picker.FileName);
    }

    private async Task InsertAssetsAsync()
    {
        var picker = new OpenFileDialog { Filter = "Pictures and PDFs|*.png;*.jpg;*.jpeg;*.bmp;*.webp;*.pdf" };
        if (picker.ShowDialog(this) != true) return;
        try { await ImportAssetAsync(picker.FileName); }
        catch (Exception ex) { UI.Error(this, ex); }
    }

    private async Task OpenPdfAsync(string path)
    {
        if (pdfBusy || !await SaveBeforeLeavingAsync()) return;
        pdfBusy = true;
        var startingBoard = editing ? Session.Board.Id : (Guid?)null;
        try
        {
            SetStatus("Reading the PDF…");
            var sheet = await pdfBook.ImportAsync(path);
            var board = await pdfBook.GetPageAsync(sheet, 1);
            if ((editing ? Session.Board.Id : (Guid?)null) == startingBoard) await OpenBoardAsync(board);
        }
        finally { pdfBusy = false; }
    }

    private async Task NavigatePdfAsync(PdfSheet sheet, int number)
    {
        if (pdfBusy || sheet.Number == number || !File.Exists(pdfBook.Original(sheet))) return;
        pdfBusy = true;
        var boardId = Session.Board.Id;
        try
        {
            if (!await SaveBeforeLeavingAsync()) return;
            var board = await pdfBook.GetPageAsync(sheet, number);
            if (editing && Session.Board.Id == boardId) await OpenBoardAsync(board);
        }
        catch (Exception ex) { UI.Error(this, ex); }
        finally { pdfBusy = false; }
    }

    private async Task BrowsePdfAsync(bool find = false)
    {
        if (pdfBusy || PdfSheet.Read(Session.Board) is not { } sheet) return;
        var original = pdfBook.Original(sheet);
        if (!File.Exists(original))
        {
            SetStatus("Open the source PDF on this PC to restore its page tools.");
            return;
        }
        Canvas.FinishStroke();
        var browser = new PdfPagesWindow(sheet, original, find) { Owner = this };
        browser.SourceInitialized += (_, _) => WindowsTheme.ApplyNative(browser);
        if (browser.ShowDialog() == true && browser.SelectedPage is int number)
            await NavigatePdfAsync(sheet, number);
    }

    private async Task ExportPdfBookAsync(IReadOnlyList<int>? pages = null)
    {
        if (pdfBusy || PdfSheet.Read(Session.Board) is not { } sheet) return;
        if (!File.Exists(pdfBook.Original(sheet)))
        {
            SetStatus("Open the source PDF on this PC before exporting its original pages.");
            return;
        }
        pdfBusy = true;
        try
        {
            if (!await SaveBeforeLeavingAsync()) return;
            if (pages is null)
            {
                var range = UI.Prompt(this, "Export PDF pages", $"Choose pages 1–{sheet.Count}, for example 1, 3–5.",
                    sheet.Number.ToString());
                if (range is null) return;
                pages = PdfBook.ParsePages(range, sheet.Count);
            }
            var picker = new SaveFileDialog
            {
                Filter = "PDF document|*.pdf", FileName = UI.Safe(Path.GetFileNameWithoutExtension(sheet.Name)) + " annotated.pdf"
            };
            if (picker.ShowDialog(this) != true) return;
            SetStatus("Exporting PDF pages…");
            await pdfBook.ExportAsync(sheet, pages, Session.Board, picker.FileName);
            SetStatus($"Exported {pages.Count} PDF page{(pages.Count == 1 ? "" : "s")}.");
        }
        catch (Exception ex) { UI.Error(this, ex); SetStatus(ex.Message); }
        finally { pdfBusy = false; }
    }
}

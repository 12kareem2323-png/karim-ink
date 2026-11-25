using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using Windows.Data.Pdf;

namespace KarimEldamatyWindows;

internal sealed class PdfPagesWindow : Window
{
    private const int Batch = 12;
    private readonly PdfSheet sheet;
    private readonly string original;
    private readonly CancellationTokenSource lifetime = new();
    private readonly WrapPanel thumbnails = new();
    private readonly TextBlock pageStatus = UI.Text("", 12, true);
    private readonly TextBlock findStatus = UI.Text("", 12, true);
    private readonly ListBox matches = new();
    private Button? previousBatch;
    private Button? nextBatch;
    private readonly TextBox text = new()
    {
        IsReadOnly = true, TextWrapping = TextWrapping.Wrap, AcceptsReturn = true,
        VerticalScrollBarVisibility = ScrollBarVisibility.Auto, MinHeight = 135
    };
    private PdfDocument? document;
    private int pageFirst;
    private int thumbnailRequest;
    private int textRequest;
    public int? SelectedPage { get; private set; }

    public PdfPagesWindow(PdfSheet sheet, string original, bool find = false)
    {
        this.sheet = sheet;
        this.original = original;
        pageFirst = (sheet.Number - 1) / Batch * Batch + 1;
        Title = "PDF pages";
        Width = 760;
        Height = 680;
        MinWidth = 490;
        MinHeight = 450;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var root = new DockPanel { Margin = new Thickness(16) };
        var heading = UI.Text(sheet.Name, 20);
        DockPanel.SetDock(heading, Dock.Top);
        root.Children.Add(heading);
        var tabs = new TabControl();
        tabs.Items.Add(new TabItem { Header = "Pages", Content = BuildPages() });
        tabs.Items.Add(new TabItem { Header = "Find text", Content = BuildFind() });
        tabs.SelectedIndex = find ? 1 : 0;
        root.Children.Add(tabs);
        Content = UI.Card(root, 0);
        Loaded += async (_, _) =>
        {
            if (find) await ShowTextAsync(sheet.Number);
            else await LoadThumbnailsAsync(pageFirst);
        };
        tabs.SelectionChanged += async (_, e) =>
        {
            if (ReferenceEquals(e.Source, tabs) && IsLoaded && tabs.SelectedIndex == 0 && thumbnails.Children.Count == 0)
                await LoadThumbnailsAsync(pageFirst);
        };
        Closed += (_, _) => lifetime.Cancel();
    }

    private UIElement BuildPages()
    {
        var root = new DockPanel { Margin = new Thickness(9) };
        var controls = new WrapPanel();
        previousBatch = UI.Button("Previous 12", () => _ = LoadThumbnailsAsync(Math.Max(1, pageFirst - Batch)));
        nextBatch = UI.Button("Next 12", () => _ = LoadThumbnailsAsync(Math.Min((sheet.Count - 1) / Batch * Batch + 1, pageFirst + Batch)));
        controls.Children.Add(previousBatch);
        controls.Children.Add(nextBatch);
        var number = new TextBox { Width = 62, Text = sheet.Number.ToString(), MaxLength = 8 };
        AutomationProperties.SetName(number, "PDF page number");
        controls.Children.Add(number);
        void Jump()
        {
            if (int.TryParse(number.Text, out var value) && value >= 1 && value <= sheet.Count) Choose(value);
            else pageStatus.Text = $"Enter a page from 1 to {sheet.Count}.";
        }
        number.KeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Enter) Jump(); };
        controls.Children.Add(UI.Button("Go to page", Jump));
        DockPanel.SetDock(controls, Dock.Top);
        DockPanel.SetDock(pageStatus, Dock.Top);
        root.Children.Add(controls);
        root.Children.Add(pageStatus);
        root.Children.Add(new ScrollViewer
        {
            Content = thumbnails, VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
        });
        return root;
    }

    private UIElement BuildFind()
    {
        var root = new DockPanel { Margin = new Thickness(10) };
        var form = new DockPanel { LastChildFill = true };
        DockPanel.SetDock(form, Dock.Top);
        var query = new TextBox { MaxLength = 256, ToolTip = "Search selectable text in this PDF" };
        AutomationProperties.SetName(query, "PDF search");
        var find = new Button { Content = "Find" };
        DockPanel.SetDock(find, Dock.Right);
        form.Children.Add(find);
        form.Children.Add(query);
        find.Click += async (_, _) =>
        {
            var term = query.Text.Trim();
            if (term.Length == 0) { query.Focus(); return; }
            find.IsEnabled = false;
            findStatus.Text = "Searching the source PDF…";
            try
            {
                var result = await PdfBook.FindTextAsync(original, term, lifetime.Token);
                if (lifetime.IsCancellationRequested) return;
                matches.ItemsSource = result.Matches;
                findStatus.Text = result.Matches.Count == 0
                    ? "No matching selectable text. Scanned pages may have no text layer."
                    : $"{result.Matches.Count}{(result.Limit ? "+" : "")} matching pages.";
            }
            catch (OperationCanceledException) { }
            catch (Exception ex) { findStatus.Text = $"Could not search the PDF. {ex.Message}"; }
            finally { find.IsEnabled = true; }
        };
        query.KeyDown += (_, e) =>
        {
            if (e.Key == System.Windows.Input.Key.Enter && find.IsEnabled) find.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        };
        root.Children.Add(form);
        DockPanel.SetDock(findStatus, Dock.Top);
        root.Children.Add(findStatus);
        var details = new StackPanel();
        details.Children.Add(UI.Text("Selectable page text", 15));
        details.Children.Add(text);
        text.Height = 155;
        var commands = new WrapPanel();
        commands.Children.Add(UI.Button("Current page text", () => _ = ShowTextAsync(sheet.Number)));
        commands.Children.Add(UI.Button("Copy page text", () =>
        {
            if (!string.IsNullOrWhiteSpace(text.Text)) Clipboard.SetText(text.Text);
        }));
        commands.Children.Add(UI.Button("Open match", () =>
        {
            if (matches.SelectedItem is PdfBook.TextMatch match) Choose(match.Page);
        }));
        details.Children.Add(commands);
        DockPanel.SetDock(details, Dock.Bottom);
        root.Children.Add(details);
        matches.ItemTemplate = BuildMatchTemplate();
        matches.SelectionChanged += (_, _) =>
        {
            if (matches.SelectedItem is PdfBook.TextMatch match) _ = ShowTextAsync(match.Page);
        };
        root.Children.Add(matches);
        return root;
    }

    private static DataTemplate BuildMatchTemplate()
    {
        var label = new FrameworkElementFactory(typeof(TextBlock));
        label.SetValue(TextBlock.TextWrappingProperty, TextWrapping.Wrap);
        var binding = new System.Windows.Data.MultiBinding { StringFormat = "Page {0}   {1}" };
        binding.Bindings.Add(new System.Windows.Data.Binding(nameof(PdfBook.TextMatch.Page)));
        binding.Bindings.Add(new System.Windows.Data.Binding(nameof(PdfBook.TextMatch.Excerpt)));
        label.SetBinding(TextBlock.TextProperty, binding);
        return new DataTemplate { VisualTree = label };
    }

    private async Task LoadThumbnailsAsync(int first)
    {
        var generation = ++thumbnailRequest;
        pageFirst = first;
        thumbnails.Children.Clear();
        var last = Math.Min(first + Batch - 1, sheet.Count);
        if (previousBatch is not null) previousBatch.IsEnabled = first > 1;
        if (nextBatch is not null) nextBatch.IsEnabled = last < sheet.Count;
        pageStatus.Text = $"Pages {first}–{last} of {sheet.Count} · Current page {sheet.Number}";
        try
        {
            document ??= await PdfBook.OpenAsync(original);
            for (var number = first; number <= last; number++)
            {
                if (lifetime.IsCancellationRequested || generation != thumbnailRequest) return;
                var image = await PdfBook.ThumbnailAsync(document, number);
                if (lifetime.IsCancellationRequested || generation != thumbnailRequest) return;
                var page = number;
                var card = new StackPanel { Width = 126 };
                card.Children.Add(new Image { Source = image, Height = 112, Stretch = Stretch.Uniform });
                card.Children.Add(UI.Text($"Page {page}{(page == sheet.Number ? " · Current" : "")}", 12));
                var button = UI.Button(card, () => Choose(page));
                AutomationProperties.SetName(button, $"Open PDF page {page}");
                thumbnails.Children.Add(button);
            }
        }
        catch (Exception ex)
        {
            if (!lifetime.IsCancellationRequested && generation == thumbnailRequest)
                pageStatus.Text = $"Unable to preview PDF pages. {ex.Message}";
        }
    }

    private async Task ShowTextAsync(int number)
    {
        var generation = ++textRequest;
        text.Clear();
        try
        {
            var value = await PdfBook.ReadTextAsync(original, number, lifetime.Token);
            if (generation != textRequest || lifetime.IsCancellationRequested) return;
            text.Text = value;
            text.ToolTip = $"Source text · Page {number}";
            if (string.IsNullOrWhiteSpace(value)) findStatus.Text = $"Page {number} has no selectable text.";
        }
        catch (OperationCanceledException) { }
        catch (Exception ex) { if (generation == textRequest) findStatus.Text = ex.Message; }
    }

    private void Choose(int number)
    {
        SelectedPage = number;
        DialogResult = true;
    }
}

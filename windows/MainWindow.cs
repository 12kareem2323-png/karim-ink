using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;

namespace KarimEldamatyWindows;

public sealed class MainWindow : Window
{
    public DrawingSession Session { get; } = new();
    public BoardStore Store { get; }
    public BoardCanvas Canvas { get; }
    private readonly Grid root = new(), home = new(), editor = new(), canvasHost = new();
    private readonly Border inspector = new GlassSurface { ShowShadow=false };
    private readonly ContentControl inspectorContent = new();
    private readonly TextBox search = new(), title = new();
    private readonly WrapPanel gallery = new();
    private readonly StackPanel folders = new();
    private readonly TextBlock status = UI.Text("Ready"), count = UI.Text(""), diagnostics = UI.Text("Mouse · constant pressure",11,true);
    private readonly ComboBox pens = new(), papers = new();
    private readonly TextBox hex = new();
    private readonly DispatcherTimer searchDelay = new(){ Interval = TimeSpan.FromMilliseconds(180) };
    private readonly Dictionary<Guid,(double Modified,BitmapSource Image)> thumbnails = [];
    private readonly Dictionary<string,Button> toolButtons = [];
    private readonly PenProfiles profiles = new();
    private AssistantPanel? assistant;
    private NotesPanel? notes;
    private UIElement? toolsPanel, symbolsPanel;
    private bool editing, switching, closing, constructing, loadingLibrary;
    private int savedRevision = -1, pageLimit = 24;
    private Task<bool>? saving;
    private string folder = "All drawings", panel = "";
    private string? activeDevice;
    private long lastInputLabel;
    private readonly ComboBox themes = new(){ItemsSource=new[]{"System","Light","Dark"},Width=96};
    public MainWindow(string? isolatedLibrary = null)
    {
        SetResourceReference(StyleProperty, typeof(Window));
        Store=new BoardStore(isolatedLibrary);Canvas=new BoardCanvas{Session=Session};
        Title="SketchGlide · 0.2 Test";Width=1370;Height=880;MinWidth=900;MinHeight=620;WindowStartupLocation=WindowStartupLocation.CenterScreen;
        SetResourceReference(BackgroundProperty,"WindowGradient"); root.Children.Add(home);root.Children.Add(editor);Content=root;editor.Visibility=Visibility.Collapsed;
        BuildHome();BuildEditor();
        Session.Changed+=SessionChanged;Session.StatusChanged+=SetStatus;Session.InputChanged+=UpdateInput;profiles.LoadProfile(Session,null);
        Store.Changed+=()=>{if(!editing&&!loadingLibrary)RenderLibrary();if(Store.Error!=null)SetStatus(Store.Error);else if(editing)SetStatus("Saved locally");};
        WindowsTheme.Changed+=()=>{themes.SelectedItem=WindowsTheme.Mode;if(editing){Canvas.Refresh();}else RenderLibrary();};
        Canvas.LineStraightened+=ShowLengthMenu;Canvas.FileDropRequested+=path=>_=OpenArgumentAsync(path);
        PreviewKeyDown+=Keys;Closing+=OnClosing;
        searchDelay.Tick+=(_,_)=>{searchDelay.Stop();pageLimit=24;RenderLibrary();};
        themes.SelectedItem=WindowsTheme.Mode;themes.SelectionChanged+=(_,_)=>{if(themes.SelectedItem is string value&&value!=WindowsTheme.Mode)WindowsTheme.SetMode(value);};
        SourceInitialized+=(_,_)=>WindowsTheme.ApplyNative(this);
    }
    public async Task InitializeAsync(){loadingLibrary=true;try{await Store.LoadAsync();}finally{loadingLibrary=false;}RenderLibrary();}
    private void BuildHome()
    {
        home.ColumnDefinitions.Add(new(){Width=new GridLength(222)});home.ColumnDefinitions.Add(new(){Width=new GridLength(1,GridUnitType.Star)});
        var sidebar=new StackPanel{Margin=new Thickness(18,26,10,16)};
        sidebar.Children.Add(UI.Text("SG",31));sidebar.Children.Add(UI.Text("SketchGlide",19));sidebar.Children.Add(UI.Text("0.2 TEST · MADE BY KAREEM",10,true));
        sidebar.Children.Add(UI.Button("Website ↗",()=>ServiceUI.OpenWeb(ReleaseSupport.Website)));
        sidebar.Children.Add(UI.Button("Feedback ↗",()=>ServiceUI.OpenWeb(ReleaseSupport.Feedback)));
        sidebar.Children.Add(UI.Button("Support with PayPal ↗",()=>ServiceUI.OpenWeb(ReleaseSupport.PayPal)));
        sidebar.Children.Add(UI.Spacer(30));sidebar.Children.Add(UI.Button("＋  New drawing",()=>_=NewBoardAsync(),true));sidebar.Children.Add(UI.Button("↗  Open drawing or PDF",()=>_=ImportDialogAsync()));
        sidebar.Children.Add(UI.Spacer(24));sidebar.Children.Add(UI.Text("YOUR LIBRARY",10,true));sidebar.Children.Add(folders);
        sidebar.Children.Add(UI.Spacer(22));sidebar.Children.Add(UI.Button("Show drawing files",()=>Process.Start(new ProcessStartInfo(Store.DirectoryPath){UseShellExecute=true})));
        sidebar.Children.Add(UI.Button("Tablet & shortcuts",ShowHelp));sidebar.Children.Add(UI.Button("AI settings",()=>ShowWindow(new AISettingsWindow(AISettingsConfig.Load()))));
        sidebar.Children.Add(UI.Text("Saved on this computer.\nDrawings stay editable on Mac and Windows.",11,true));
        var sidebarCard=UI.Card(sidebar,0);sidebarCard.Margin=new Thickness(12,12,0,12);home.Children.Add(sidebarCard);
        var main=new Grid{Margin=new Thickness(30,26,24,16)};main.RowDefinitions.Add(new(){Height=GridLength.Auto});main.RowDefinitions.Add(new(){Height=GridLength.Auto});main.RowDefinitions.Add(new(){Height=new GridLength(1,GridUnitType.Star)});main.RowDefinitions.Add(new(){Height=GridLength.Auto});Grid.SetColumn(main,1);home.Children.Add(main);
        var header=new Grid();header.ColumnDefinitions.Add(new(){Width=new GridLength(1,GridUnitType.Star)});header.ColumnDefinitions.Add(new(){Width=GridLength.Auto});
        var welcome=new StackPanel();welcome.Children.Add(UI.Text("Space for your next idea.",29));welcome.Children.Add(UI.Text("Sketch, solve and build — a personal space for your ideas.",13,true));header.Children.Add(welcome);
        var appearance=new StackPanel{Orientation=Orientation.Horizontal,VerticalAlignment=VerticalAlignment.Top};appearance.Children.Add(UI.Button("◐",WindowsTheme.Toggle));appearance.Children.Add(themes);Grid.SetColumn(appearance,1);header.Children.Add(appearance);main.Children.Add(header);
        var starterSection=new StackPanel{Margin=new Thickness(0,26,0,20)};
        starterSection.Children.Add(UI.Text("START SOMETHING",10,true));var starters=new WrapPanel();
        foreach(var (label,detail,paper) in new[]{("Blank canvas","Room to think","Plain"),("Engineering","Precise grids & mm","Engineering sheet"),("Mathematics","Notation & graphs","Graph paper"),("3D sketches","Simple shapes in space","Isometric")})
        {var inner=new StackPanel{Width=166,Margin=new Thickness(3,8,3,8)};inner.Children.Add(UI.Text(label,16));inner.Children.Add(UI.Text(detail,11,true));starters.Children.Add(UI.Button(inner,()=>_=NewBoardAsync(paper,label=="3D sketches")));}starterSection.Children.Add(starters);
        var filter=new DockPanel{Margin=new Thickness(0,24,0,0)};count.FontSize=18;count.VerticalAlignment=VerticalAlignment.Center;filter.Children.Add(count);search.Width=280;search.ToolTip="Search titles, notes and folders";search.TextChanged+=(_,_)=>{searchDelay.Stop();searchDelay.Start();};DockPanel.SetDock(search,Dock.Right);filter.Children.Add(search);starterSection.Children.Add(filter);Grid.SetRow(starterSection,1);main.Children.Add(starterSection);
        var scroll=new ScrollViewer{Content=gallery,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled};Grid.SetRow(scroll,2);main.Children.Add(scroll);
        var footer=UI.Text("Windows 11 · Drawing, symbols and local saving work offline",11,true);footer.Margin=new Thickness(0,12,0,0);Grid.SetRow(footer,3);main.Children.Add(footer);
    }
    private void BuildEditor()
    {
        editor.RowDefinitions.Add(new(){Height=GridLength.Auto});editor.RowDefinitions.Add(new(){Height=new GridLength(1,GridUnitType.Star)});editor.RowDefinitions.Add(new(){Height=GridLength.Auto});
        var header=new Grid{Margin=new Thickness(12,10,12,7)};header.ColumnDefinitions.Add(new(){Width=GridLength.Auto});header.ColumnDefinitions.Add(new(){Width=new GridLength(1,GridUnitType.Star)});header.ColumnDefinitions.Add(new(){Width=GridLength.Auto});
        header.Children.Add(UI.Button("‹  Library",()=>_=HomeAsync()));title.Background=Brushes.Transparent;title.BorderThickness=new Thickness(0);title.FontSize=17;title.FontWeight=FontWeights.SemiBold;title.VerticalContentAlignment=VerticalAlignment.Center;title.ToolTip="Drawing title";title.LostKeyboardFocus+=(_,_)=>SaveTitle();Grid.SetColumn(title,1);header.Children.Add(title);
        var actions=new WrapPanel{VerticalAlignment=VerticalAlignment.Center};actions.Children.Add(UI.Button("Math",()=>ShowWindow(new MathWindow(Session))));actions.Children.Add(UI.Button("3D",()=>ShowWindow(new Sketch3DWindow(Session))));actions.Children.Add(UI.Button("Calculate",()=>ShowWindow(new EngineeringWindow(Session))));actions.Children.Add(UI.Button("Symbols",()=>TogglePanel("Symbols")));actions.Children.Add(UI.Button("AI",()=>TogglePanel("AI")));actions.Children.Add(UI.Button("Notes",()=>TogglePanel("Notes")));actions.Children.Add(UI.Button("◐",WindowsTheme.Toggle));actions.Children.Add(UI.Button("Export ↗",ShowExportMenu));actions.Children.Add(UI.Button("⚙",()=>TogglePanel("Tools")));Grid.SetColumn(actions,2);header.Children.Add(actions);editor.Children.Add(header);
        var workspace=new Grid{Margin=new Thickness(12,0,12,0)};workspace.ColumnDefinitions.Add(new(){Width=new GridLength(1,GridUnitType.Star)});workspace.ColumnDefinitions.Add(new(){Width=GridLength.Auto});Grid.SetRow(workspace,1);editor.Children.Add(workspace);
        var canvasCard=UI.Card(canvasHost,0);canvasCard.CornerRadius=new CornerRadius(18);canvasCard.ClipToBounds=true;workspace.Children.Add(canvasCard);canvasHost.Children.Add(Canvas);
        var floating=new WrapPanel{HorizontalAlignment=HorizontalAlignment.Center};
        foreach(var (name,label) in new[]{("Draw","✎ Draw"),("Eraser","Eraser"),("Select","Select"),("Lasso","Lasso"),("Line","╱"),("Rectangle","▭"),("Ellipse","○"),("Triangle","△"),("Arrow","↗"),("Dimension","↔ mm"),("Text","T")})
        {var toolName=name;var button=UI.Button(label,()=>SetTool(toolName));button.ToolTip=toolName;toolButtons[name]=button;floating.Children.Add(button);}
        pens.ItemsSource=BrushSettings.PenNames;pens.SelectedItem=Session.Pen;pens.Width=144;pens.SelectionChanged+=(_,_)=>{if(!constructing&&pens.SelectedItem is string value){Canvas.FinishStroke();profiles.SaveProfile(Session,activeDevice);Session.SetPen(value);profiles.LoadProfile(Session,activeDevice);if(panel=="Tools"){toolsPanel=null;ShowPanel("Tools");}}};floating.Children.Add(pens);
        floating.Children.Add(UI.Button("↶",()=>{Canvas.FinishStroke();Session.Undo();}));floating.Children.Add(UI.Button("↷",()=>{Canvas.FinishStroke();Session.Redo();}));floating.Children.Add(UI.Button("−",()=>Zoom(.8)));floating.Children.Add(UI.Button("Fit",Canvas.FitBoard));floating.Children.Add(UI.Button("＋",()=>Zoom(1.25)));
        var bar=UI.Card(floating,5);bar.HorizontalAlignment=HorizontalAlignment.Center;bar.VerticalAlignment=VerticalAlignment.Bottom;bar.MaxWidth=1020;bar.Margin=new Thickness(12,0,12,18);canvasHost.Children.Add(bar);
        var hoverHint=UI.Text("Space + drag to pan   ·   Wheel to zoom   ·   Hold a stroke for ½ second to straighten",11,true);var hintCard=UI.Card(hoverHint,7);hintCard.HorizontalAlignment=HorizontalAlignment.Left;hintCard.VerticalAlignment=VerticalAlignment.Top;hintCard.Margin=new Thickness(14);hintCard.IsHitTestVisible=false;canvasHost.Children.Add(hintCard);
        inspector.Width=334;inspector.Margin=new Thickness(10,0,0,0);inspector.CornerRadius=new CornerRadius(18);inspector.SetResourceReference(Border.BackgroundProperty,"CardBrush");inspector.SetResourceReference(Border.BorderBrushProperty,"BorderBrush");inspector.BorderThickness=new Thickness(.6);inspector.Visibility=Visibility.Collapsed;inspector.Child=inspectorContent;Grid.SetColumn(inspector,1);workspace.Children.Add(inspector);
        var footer=new DockPanel{Margin=new Thickness(22,8,22,10)};diagnostics.HorizontalAlignment=HorizontalAlignment.Right;DockPanel.SetDock(diagnostics,Dock.Right);footer.Children.Add(diagnostics);status.FontSize=11;status.TextTrimming=TextTrimming.CharacterEllipsis;footer.Children.Add(status);Grid.SetRow(footer,2);editor.Children.Add(footer);
        SetTool("Draw");
    }
    private void RenderLibrary()
    {
        if(editing)return;folders.Children.Clear();foreach(var f in new[]{"All drawings"}.Concat(Store.Boards.Select(b=>b.Folder).Distinct().Order())){var name=f;var button=UI.Button(name,()=>{folder=name;pageLimit=24;RenderLibrary();});if(name==folder)button.SetResourceReference(Control.BorderBrushProperty,"AccentBrush");folders.Children.Add(button);}
        var q=search.Text.Trim();var all=Store.Boards.Where(b=>(folder=="All drawings"||b.Folder==folder)&&(q.Length==0||b.Title.Contains(q,StringComparison.OrdinalIgnoreCase)||b.Notes.Contains(q,StringComparison.OrdinalIgnoreCase)||b.Folder.Contains(q,StringComparison.OrdinalIgnoreCase))).OrderByDescending(b=>b.Modified).ToList();count.Text=all.Count+" drawings";gallery.Children.Clear();
        if(all.Count==0){var empty=new StackPanel{Margin=new Thickness(12,36,12,24)};empty.Children.Add(UI.Text(q.Length==0?"Your ideas start here.":"No matching drawings",23));empty.Children.Add(UI.Text(q.Length==0?"Choose a canvas above, or import an existing drawing.":"Try a title, folder or a word from your notes.",13,true));gallery.Children.Add(empty);}
        foreach(var b in all.Take(pageLimit))
        {var drawing=b;var cardContent=new StackPanel{Width=235};try{if(!thumbnails.TryGetValue(b.Id,out var cached)||cached.Modified!=b.Modified){cached=(b.Modified,BoardExport.RenderBitmap(b,true,380));thumbnails[b.Id]=cached;if(thumbnails.Count>48)thumbnails.Remove(thumbnails.Keys.First(k=>k!=b.Id));}cardContent.Children.Add(new Image{Source=cached.Image,Height=154,Stretch=Stretch.Uniform,Margin=new Thickness(0,0,0,12)});}catch(Exception){cardContent.Children.Add(UI.Text("Drawing preview",20,true));}
            var name=UI.Text(b.Title,15);name.TextTrimming=TextTrimming.CharacterEllipsis;cardContent.Children.Add(name);cardContent.Children.Add(UI.Text(b.Folder+" · "+SwiftDate.ToDate(b.Modified).LocalDateTime.ToString("dd MMM, HH:mm"),10,true));
            var card=UI.Button(cardContent,()=>_=OpenBoardAsync(drawing));card.Padding=new Thickness(15);card.Margin=new Thickness(0,0,14,14);card.ContextMenu=LibraryMenu(drawing);gallery.Children.Add(card);}
        if(all.Count>pageLimit)gallery.Children.Add(UI.Button("Show more drawings",()=>{pageLimit+=24;RenderLibrary();}));
        if(Store.Error!=null){var warning=UI.Text("Library notice: "+Store.Error,11,true);warning.MaxWidth=700;gallery.Children.Add(warning);}
    }
    private ContextMenu LibraryMenu(Board b)
    {
        var menu=new ContextMenu();UI.Menu(menu,"Open",()=>_=OpenBoardAsync(b));UI.Menu(menu,"Duplicate",async()=>{var copy=BoardCodec.Clone(b);copy.Id=Guid.NewGuid();copy.Title+=" copy";copy.Created=copy.Modified=SwiftDate.Now;await Store.SaveAsync(copy);RenderLibrary();});
        UI.Menu(menu,"Move to folder…",async()=>{var value=UI.Prompt(this,"Move drawing","Folder name",b.Folder);if(value is null)return;var copy=BoardCodec.Clone(b);copy.Folder=value.Trim().Length==0?"General":value.Trim();copy.Modified=SwiftDate.Now;await Store.SaveAsync(copy);RenderLibrary();});
        UI.Menu(menu,"Export editable .engboard",()=>ExportBoard(b));UI.Menu(menu,"Archive drawing",async()=>{if(MessageBox.Show(this,"Archive this drawing? It can be recovered from the Archive/Deleted folder.",b.Title,MessageBoxButton.YesNo)==MessageBoxResult.Yes){await Store.DeleteAsync(b);thumbnails.Remove(b.Id);RenderLibrary();}});return menu;
    }
    public async Task NewBoardAsync(string background="Square grid",bool sketch=false)
    {if(!await SaveBeforeLeavingAsync())return;var b=new Board{Title="Untitled drawing",Background=background};if(!await Store.SaveAsync(b)){SetStatus(Store.Error??"Could not create the drawing.");return;}await OpenBoardAsync(b);if(sketch)ShowWindow(new Sketch3DWindow(Session));}
    public async Task OpenBoardAsync(Board board)
    {
        if(editing&&Session.Board.Id==board.Id)return;if(!await SaveBeforeLeavingAsync())return;
        Canvas.FinishStroke();switching=true;try{Session.SetBoard(board);savedRevision=Session.Revision;title.Text=board.Title;editing=true;home.Visibility=Visibility.Collapsed;editor.Visibility=Visibility.Visible;assistant=null;notes=null;toolsPanel=null;symbolsPanel=null;panel="";inspectorContent.Content=null;inspector.Visibility=Visibility.Collapsed;}finally{switching=false;}
        await Dispatcher.InvokeAsync(Canvas.FitBoard,DispatcherPriority.Loaded);Canvas.Focus();SetStatus("Saved locally · "+board.Background);
    }
    public async Task HomeAsync(){if(!await SaveBeforeLeavingAsync())return;Canvas.FinishStroke();editing=false;editor.Visibility=Visibility.Collapsed;home.Visibility=Visibility.Visible;inspectorContent.Content=null;RenderLibrary();}
    private void SaveTitle(){if(!editing||switching)return;var text=title.Text.Trim();if(text.Length==0)text="Untitled drawing";if(text==Session.Board.Title)return;Session.Checkpoint();Session.Board.Title=text;title.Text=text;Session.NotifyChanged();}
    private void SessionChanged()
    {if(!editing||switching)return;if(!title.IsKeyboardFocusWithin)title.Text=Session.Board.Title;if(savedRevision!=Session.Revision){Store.ScheduleSave(Session.Board);savedRevision=Session.Revision;SetStatus("Saving locally…");}UpdateTools();}
    private async Task<bool> SaveBeforeLeavingAsync()
    {
        if(!editing)return true;if(saving!=null)return await saving;
        var completion=new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);saving=completion.Task;root.IsEnabled=false;
        try
        {
            Canvas.FinishStroke();SaveTitle();await Store.FlushAsync();bool result;
            if(await Store.SaveAsync(Session.Board)){SetStatus("Saved locally");result=true;}
            else
            {
                var answer=MessageBox.Show(this,(Store.Error??"Saving failed.")+"\n\nSave your edits as a new drawing?","Drawing needs attention",MessageBoxButton.YesNo,MessageBoxImage.Warning);
                result=false;
                if(answer==MessageBoxResult.Yes){var copy=BoardCodec.Clone(Session.Board);copy.Id=Guid.NewGuid();copy.Title+=" recovered";copy.Created=copy.Modified=SwiftDate.Now;if(await Store.SaveAsync(copy)){switching=true;try{Session.SetBoard(copy);}finally{switching=false;}title.Text=copy.Title;savedRevision=Session.Revision;result=true;}}
            }
            completion.TrySetResult(result);return result;
        }
        catch(Exception ex){completion.TrySetResult(false);UI.Error(this,ex);return false;}
        finally{root.IsEnabled=true;saving=null;}
    }
    private async void OnClosing(object? sender,CancelEventArgs e)
    {
        if(closing)return;e.Cancel=true;
        foreach(var owned in OwnedWindows.Cast<Window>().ToArray()){owned.Close();if(owned.IsVisible)return;}
        if(await SaveBeforeLeavingAsync()){profiles.SaveProfile(Session,activeDevice);profiles.Flush();closing=true;Store.Dispose();Close();}
    }
    public async Task OpenArgumentAsync(string path)
    {
        try{if(Uri.TryCreate(path,UriKind.Absolute,out var uri)&&uri.Scheme=="karimboard"){var idText=uri.Host=="board"?uri.AbsolutePath.Trim('/'):uri.Host;if(!Guid.TryParse(idText,out var id))throw new InvalidDataException("This drawing link has no valid board identifier.");var b=Store.Boards.FirstOrDefault(x=>x.Id==id)??throw new FileNotFoundException("This drawing is not saved on this computer. Import its .engboard file first.");await OpenBoardAsync(b);return;}
            if(!File.Exists(path))throw new FileNotFoundException("Drawing file not found.",path);
            if(Path.GetExtension(path).Equals(".engboard",StringComparison.OrdinalIgnoreCase)){var imported=await Task.Run(()=>BoardCodec.Read(path));imported.Id=Guid.NewGuid();imported.Modified=SwiftDate.Now;if(!await SaveBeforeLeavingAsync())return;if(!await Store.SaveAsync(imported))throw new IOException(Store.Error);await OpenBoardAsync(imported);SetStatus("Imported an editable copy. The original file stays intact.");}
            else{if(!editing)await NewBoardAsync();if(editing)await ImportAssetAsync(path);}}
        catch(Exception ex){UI.Error(this,ex);}
    }
    private async Task ImportDialogAsync(){var d=new OpenFileDialog{Filter="Drawings, pictures and PDFs|*.engboard;*.png;*.jpg;*.jpeg;*.bmp;*.webp;*.pdf|Editable drawing|*.engboard|All files|*.*"};if(d.ShowDialog(this)==true)await OpenArgumentAsync(d.FileName);}
    private async Task ImportAssetAsync(string path)
    {
        var boardId=Session.Board.Id;
        if(new FileInfo(path).Length>100*1024*1024)throw new InvalidDataException("Choose a file smaller than 100 MB.");
        var point=Canvas.WorldPoint(new Point(Math.Max(70,Canvas.ActualWidth/3),Math.Max(70,Canvas.ActualHeight/3)));
        if(Path.GetExtension(path).Equals(".pdf",StringComparison.OrdinalIgnoreCase))
        {var file=await Windows.Storage.StorageFile.GetFileFromPathAsync(Path.GetFullPath(path));var pdf=await Windows.Data.Pdf.PdfDocument.LoadFromFileAsync(file);var requested=UI.Prompt(this,"Import PDF pages","Pages, for example 1 or 1-3 (maximum 12)","1");if(requested is null)return;var range=requested.Split('-');if(!int.TryParse(range[0],out var first)||!int.TryParse(range.Length>1?range[1]:range[0],out var last)||first<1||last<first||last>pdf.PageCount||last-first>=12)throw new ArgumentException("Enter a valid page range containing up to 12 pages.");
            for(var n=first;n<=last;n++){using var page=pdf.GetPage((uint)n-1);using var stream=new Windows.Storage.Streams.InMemoryRandomAccessStream();await page.RenderToStreamAsync(stream,new Windows.Data.Pdf.PdfPageRenderOptions{DestinationWidth=1600});if(stream.Size>24*1024*1024)throw new InvalidDataException("PDF page image is too large.");using var reader=new Windows.Storage.Streams.DataReader(stream.GetInputStreamAt(0));await reader.LoadAsync((uint)stream.Size);var data=new byte[stream.Size];reader.ReadBytes(data);if(Session.Board.Id!=boardId){SetStatus("PDF import stopped because you changed drawings.");return;}Canvas.AddImage(data,new Point(point.X,point.Y+(n-first)*1100));}SetStatus("PDF pages inserted as images.");}
        else{var bytes=await File.ReadAllBytesAsync(path);if(Session.Board.Id!=boardId){SetStatus("Image import stopped because you changed drawings.");return;}Canvas.AddImage(bytes,point);SetStatus("Image inserted. Select it to resize.");}
    }
    private void SetTool(string tool){Canvas.FinishStroke();Session.Tool=tool;Session.PendingSymbolId=null;if(tool!="Select"&&tool!="Lasso")Session.SelectedIds.Clear();Session.NotifyViewChanged();UpdateTools();Canvas.Focus();}
    private void UpdateTools(){foreach(var pair in toolButtons){pair.Value.SetResourceReference(Control.BorderBrushProperty,pair.Key==Session.Tool?"AccentBrush":"BorderBrush");pair.Value.FontWeight=pair.Key==Session.Tool?FontWeights.SemiBold:FontWeights.Normal;}}
    private void Zoom(double factor)=>Canvas.ZoomAt(new Point(Canvas.ActualWidth/2,Canvas.ActualHeight/2),factor);
    private void TogglePanel(string name){if(panel==name&&inspector.Visibility==Visibility.Visible){Canvas.FinishStroke();inspector.Visibility=Visibility.Collapsed;inspectorContent.Content=null;panel="";}else ShowPanel(name);}
    public void ShowPanel(string name)
    {
        Canvas.FinishStroke();panel=name;inspector.Visibility=Visibility.Visible;
        inspectorContent.Content=name switch{"AI"=>assistant??=new AssistantPanel(Session),"Notes"=>notes??=new NotesPanel(Session),"Symbols"=>symbolsPanel??=BuildSymbols(),_=>toolsPanel??=BuildTools()};
    }
    private UIElement BuildTools()
    {
        constructing=true;var stack=new StackPanel{Margin=new Thickness(16)};stack.Children.Add(UI.Text("Make it yours",22));stack.Children.Add(UI.Text("Pen, paper & precision",12,true));stack.Children.Add(UI.Spacer(12));
        var chooser=new ComboBox{ItemsSource=BrushSettings.PenNames,SelectedItem=Session.Pen};chooser.SelectionChanged+=(_,_)=>{if(constructing)return;pens.SelectedItem=chooser.SelectedItem;};stack.Children.Add(UI.Text("Pen",13));stack.Children.Add(chooser);
        var palette=new WrapPanel();foreach(var color in InkColor.Palette){var ink=color;var swatch=UI.Button("●",()=>SetColor(ink));swatch.Foreground=ink.Brush();swatch.FontSize=22;swatch.Padding=new Thickness(8,3,8,3);palette.Children.Add(swatch);}stack.Children.Add(palette);
        hex.Text=ColorToHex(Session.Color);hex.ToolTip="Ink hex colour, e.g. #2463D9";hex.LostKeyboardFocus+=(_,_)=>ApplyHex();hex.KeyDown+=(_,e)=>{if(e.Key==Key.Enter){ApplyHex();e.Handled=true;}};if(hex.Parent is Panel parent)parent.Children.Remove(hex);stack.Children.Add(hex);stack.Children.Add(UI.Button("Native colour wheel…",()=>{var chosen=NativeColorPicker.Pick(this,Session.Color);if(chosen!=null)SetColor(chosen);}));
        foreach(var channel in new[]{"R","G","B"}){var label=channel;var value=label=="R"?Session.Color.R:label=="G"?Session.Color.G:Session.Color.B;UI.Slider(stack,label,0,255,value*255,v=>{var c=Session.Color;SetColor(new InkColor(label=="R"?v/255:c.R,label=="G"?v/255:c.G,label=="B"?v/255:c.B,c.A));});}
        stack.Children.Add(UI.Text("Pressure & texture",16));UI.Check(stack,"Use pen pressure",Session.Settings.PressureEnabled,v=>{Session.Settings.PressureEnabled=v;SaveProfile();});
        stack.Children.Add(UI.Text("Eraser",13));var eraserMode=new ComboBox{ItemsSource=new[]{"Stroke","Partial"},SelectedItem=Session.EraserMode};eraserMode.SelectionChanged+=(_,_)=>{Session.EraserMode=eraserMode.SelectedItem as string??"Stroke";SaveProfile();};stack.Children.Add(eraserMode);UI.Slider(stack,"Eraser radius",3,100,Session.EraserRadius,v=>{Session.EraserRadius=v;SaveProfile();});stack.Children.Add(UI.Text("Pen side button",12));var barrel=new ComboBox{ItemsSource=new[]{"Pan","Context menu","None"},SelectedItem=Session.BarrelButtonAction};barrel.SelectionChanged+=(_,_)=>{Session.BarrelButtonAction=barrel.SelectedItem as string??"Pan";SaveProfile();};stack.Children.Add(barrel);
        UI.Slider(stack,"Minimum width",.2,30,Session.Settings.MinWidth,v=>{Session.Settings.MinWidth=v;Session.Settings.MaxWidth=Math.Max(Session.Settings.MaxWidth,v);SaveProfile();});
        UI.Slider(stack,"Maximum width",.2,80,Session.Settings.MaxWidth,v=>{Session.Settings.MaxWidth=Math.Max(v,Session.Settings.MinWidth);SaveProfile();});
        UI.Slider(stack,"Pressure curve",.15,4,Session.Settings.PressureGamma,v=>{Session.Settings.PressureGamma=v;SaveProfile();});
        UI.Slider(stack,"Opacity",.05,1,Session.Settings.Opacity,v=>{Session.Settings.Opacity=v;SaveProfile();});
        UI.Slider(stack,"Minimum pressure opacity",0,1,Session.Settings.MinOpacity,v=>{Session.Settings.MinOpacity=v;Session.Settings.MaxOpacity=Math.Max(v,Session.Settings.MaxOpacity);SaveProfile();});
        UI.Slider(stack,"Maximum pressure opacity",0,1,Session.Settings.MaxOpacity,v=>{Session.Settings.MaxOpacity=Math.Max(v,Session.Settings.MinOpacity);SaveProfile();});
        UI.Slider(stack,"Texture",.2,3,Session.Settings.TextureScale,v=>{Session.Settings.TextureScale=v;SaveProfile();});
        UI.Slider(stack,"Pen activation force",0,.35,Session.ActivationPressure,v=>{Session.ActivationPressure=v;SaveProfile();});
        var grade=new ComboBox{ItemsSource=new[]{"2H","H","HB","2B","4B","6B"},SelectedItem=Session.Settings.PencilGrade};grade.SelectionChanged+=(_,_)=>{Session.Settings.PencilGrade=grade.SelectedItem as string??"HB";SaveProfile();};stack.Children.Add(UI.Text("Pencil grade",12));stack.Children.Add(grade);
        UI.Slider(stack,"Stroke smoothing",0,1,Session.Smoothing,v=>Session.Smoothing=v);stack.Children.Add(UI.Button("Test your tablet…",ShowHelp));stack.Children.Add(UI.Text("Profiles are saved separately for each detected pen device. The driver must expose pressure and tilt; check the status below with your physical pen.",11,true));stack.Children.Add(UI.Button("Reset this pen profile",()=>{Session.Settings=BrushSettings.Defaults(Session.Pen);SaveProfile();toolsPanel=null;ShowPanel("Tools");}));
        stack.Children.Add(UI.Spacer(14));stack.Children.Add(UI.Text("Paper & geometry",16));papers.ItemsSource=Board.BackgroundNames;papers.SelectedItem=Session.Board.Background;papers.SelectionChanged+=(_,_)=>{if(constructing||papers.SelectedItem is not string value||value==Session.Board.Background)return;Session.Checkpoint();Session.Board.Background=value;Session.NotifyChanged();};if(papers.Parent is Panel pp)pp.Children.Remove(papers);stack.Children.Add(papers);
        UI.Check(stack,"Hold to correct shapes (½ second)",Session.AutoCorrect,v=>Session.AutoCorrect=v);UI.Check(stack,"Snap to grid / isometric angles",Session.Snap,v=>Session.Snap=v);UI.Check(stack,"Ruler",Session.ShowRuler,v=>{Session.ShowRuler=v;Session.NotifyViewChanged();});UI.Check(stack,"Protractor",Session.ShowProtractor,v=>{Session.ShowProtractor=v;Session.NotifyViewChanged();});UI.Check(stack,"Animate inserted diagrams briefly",Session.ShowSymbolAnimations,v=>Session.ShowSymbolAnimations=v);
        UI.Numeric(stack,"Grid spacing (drawing points)",Session.Board.GridSpacing,v=>{Session.Checkpoint();Session.Board.GridSpacing=Math.Clamp(v,5,300);Session.NotifyChanged();});UI.Numeric(stack,"Drawing points per millimetre",Session.Board.PointsPerMM,v=>{Session.Checkpoint();Session.Board.PointsPerMM=Math.Clamp(v,.1,100);Session.NotifyChanged();});UI.Numeric(stack,"Scale denominator · 1 :",Session.Board.ScaleDenominator,v=>{Session.Checkpoint();Session.Board.ScaleDenominator=Math.Clamp(v,1,100000);Session.NotifyChanged();});UI.Numeric(stack,"Fixed line length (mm; 0 = free)",Session.FixedLineLengthMM,v=>Session.FixedLineLengthMM=Math.Clamp(v,0,100000));
        var dash=new ComboBox{ItemsSource=new[]{"Solid","Dashed","Dotted","Centre"},SelectedItem=Session.Dash};dash.SelectionChanged+=(_,_)=>Session.Dash=dash.SelectedItem as string??"Solid";stack.Children.Add(dash);UI.Check(stack,"Fill new shapes",Session.FillShapes,v=>Session.FillShapes=v);UI.Check(stack,"Reduce transparency",WindowsTheme.ReduceTransparency,WindowsTheme.SetReduceTransparency);stack.Children.Add(UI.Text("Glass appearance",12));var material=new ComboBox{ItemsSource=new[]{"Balanced","Frosted","Solid"},SelectedItem=WindowsTheme.GlassMaterial};material.SelectionChanged+=(_,_)=>{if(material.SelectedItem is string choice)WindowsTheme.SetGlassMaterial(choice);};stack.Children.Add(material);stack.Children.Add(UI.Text("Balanced uses efficient Mica. Frosted uses Windows Acrylic. Solid reduces visual effects.",11,true));
        stack.Children.Add(UI.Text("Selection",16));stack.Children.Add(UI.Button("Copy selection",()=>{Canvas.FinishStroke();BoardClipboard.Copy(Session);}));stack.Children.Add(UI.Button("Cut selection",()=>{Canvas.FinishStroke();BoardClipboard.Cut(Session);}));stack.Children.Add(UI.Button("Duplicate selection",()=>{Canvas.FinishStroke();Session.DuplicateSelection();}));stack.Children.Add(UI.Button("Delete selection",()=>{Canvas.FinishStroke();Session.DeleteSelection();}));stack.Children.Add(UI.Button("Lock / unlock selection",()=>{if(Session.SelectedIds.Count==0)return;Session.Checkpoint();foreach(var e in Session.Board.Elements.Where(e=>Session.SelectedIds.Contains(e.Id)))e.Locked=!e.Locked;Session.NotifyChanged();}));stack.Children.Add(UI.Button("Review handwriting & spelling",()=>ShowWindow(new HandwritingReviewWindow(Session))));
        UI.Numeric(stack,"Page width (points)",Session.Board.Width,v=>{Session.Checkpoint();Session.Board.Width=Math.Clamp(v,200,30000);Session.NotifyChanged();});UI.Numeric(stack,"Page height (points)",Session.Board.Height,v=>{Session.Checkpoint();Session.Board.Height=Math.Clamp(v,200,30000);Session.NotifyChanged();});
        constructing=false;return new ScrollViewer{Content=stack,VerticalScrollBarVisibility=ScrollBarVisibility.Auto};
    }
    private void SetColor(InkColor color){Session.Color=color;hex.Text=ColorToHex(color);Session.NotifyViewChanged();SaveProfile();}
    private static string ColorToHex(InkColor c)=>$"#{(byte)(Math.Clamp(c.R,0,1)*255):X2}{(byte)(Math.Clamp(c.G,0,1)*255):X2}{(byte)(Math.Clamp(c.B,0,1)*255):X2}";
    private void ApplyHex(){try{var c=(Color)ColorConverter.ConvertFromString(hex.Text);SetColor(new InkColor(c.R/255d,c.G/255d,c.B/255d,c.A/255d));}catch{hex.Text=ColorToHex(Session.Color);SetStatus("Use a colour such as #2463D9.");}}
    private void SaveProfile(){if(!constructing)profiles.SaveProfile(Session,activeDevice);}
    private void UpdateInput()
    {
        if(activeDevice!=Session.InputDeviceKey){profiles.SaveProfile(Session,activeDevice);activeDevice=Session.InputDeviceKey;profiles.LoadProfile(Session,activeDevice);toolsPanel=null;}
        var now=Stopwatch.GetTimestamp();if((now-lastInputLabel)/(double)Stopwatch.Frequency<1/30d)return;lastInputLabel=now;
        var capability=Session.InputCapabilities;
        diagnostics.Text=Session.PenActive?$"{capability.DeviceName} · pressure {(Session.LivePressure is {} p?p.ToString("P0"):"unavailable")} · tilt {(capability.TiltXSupported||capability.TiltYSupported?$"{Session.LiveTilt.X*90:0}° / {Session.LiveTilt.Y*90:0}°":"unavailable")}":$"Mouse · {Session.Pen} · {Session.Zoom:P0}";
        diagnostics.ToolTip=Session.PenActive?capability.IdentitySource:"Connect a tablet with a Windows Ink driver to use pressure and supported pen features.";
    }
    private UIElement BuildSymbols() => new SymbolLibraryPanel(Session);
    private void ShowLengthMenu(DrawingElement element)
    {
        if(element.Points.Count<2)return;var a=element.Points[0].Point;var b=element.Points[^1].Point;var mm=Session.Board.Millimetres((b-a).Length);
        var popup=new System.Windows.Controls.Primitives.Popup{PlacementTarget=Canvas,Placement=System.Windows.Controls.Primitives.PlacementMode.Relative,AllowsTransparency=true,StaysOpen=false};var p=Canvas.ScreenPoint(b);popup.HorizontalOffset=Math.Clamp(p.X,0,Math.Max(0,Canvas.ActualWidth-220));popup.VerticalOffset=Math.Clamp(p.Y+12,0,Math.Max(0,Canvas.ActualHeight-90));
        var stack=new StackPanel();stack.Children.Add(UI.Text("Exact length · mm",12));var value=new TextBox{Text=mm.ToString("0.##",CultureInfo.InvariantCulture),Width=150};stack.Children.Add(value);stack.Children.Add(UI.Button("Set length",()=>{if(!double.TryParse(value.Text.Trim().Replace("mm","",StringComparison.OrdinalIgnoreCase),NumberStyles.Float,CultureInfo.InvariantCulture,out var length)||!double.IsFinite(length)||length<=0||length>1e6){SetStatus("Enter a positive millimetre length.");return;}var current=Session.Board.Elements.FirstOrDefault(e=>e.Id==element.Id);if(current is null||current.Locked)return;var vector=b-a;if(vector.Length<.001)return;vector.Normalize();var endpoint=DrawingMath.FixedEndpoint(new(a.X,a.Y),new(b.X,b.Y),length,Session.Board.PointsPerMM,Session.Board.ScaleDenominator);if(endpoint is null){SetStatus("That length exceeds the supported drawing coordinates.");return;}Session.Checkpoint();current.Points=[new(a.X,a.Y),endpoint];Session.NotifyChanged();popup.IsOpen=false;}));popup.Child=UI.Card(stack,12);popup.IsOpen=true;
    }
    private void ShowExportMenu()
    {
        Canvas.FinishStroke();SaveTitle();var menu=new ContextMenu();UI.Menu(menu,"Editable drawing (.engboard)",()=>ExportBoard(Session.Board));UI.Menu(menu,"Image (PNG / JPEG)",()=>{var d=new SaveFileDialog{Filter="PNG image|*.png|JPEG image|*.jpg",FileName=UI.Safe(Session.Board.Title)+".png"};if(d.ShowDialog(this)==true)Try(()=>BoardExport.ExportImage(Session.Board,d.FileName));});
        UI.Menu(menu,"PDF",()=>{var d=new SaveFileDialog{Filter="PDF document|*.pdf",FileName=UI.Safe(Session.Board.Title)+".pdf"};if(d.ShowDialog(this)==true)Try(()=>BoardExport.ExportPDF(Session.Board,d.FileName));});UI.Menu(menu,"Editable Excalidraw / Craft copy",()=>{var d=new SaveFileDialog{Filter="Excalidraw|*.excalidraw",FileName=UI.Safe(Session.Board.Title)+".excalidraw"};if(d.ShowDialog(this)==true)Try(()=>CraftExchange.ExportExcalidraw(Session.Board,d.FileName));});UI.Menu(menu,"Notion HTML drawing copy",()=>{var d=new SaveFileDialog{Filter="HTML|*.html",FileName=UI.Safe(Session.Board.Title)+".html"};if(d.ShowDialog(this)==true)Try(()=>NotionHTMLExport.ExportNotionHtml(Session.Board,d.FileName,BoardExport.RenderPNG(Session.Board)));});UI.Menu(menu,"Copy selection",()=>BoardClipboard.Copy(Session));UI.Menu(menu,"Cut selection",()=>BoardClipboard.Cut(Session));UI.Menu(menu,"Paste",Canvas.Paste);UI.Menu(menu,"Copy native drawing link",()=>Try(()=>Clipboard.SetText(CraftExchange.NativeLink(Session.Board))));UI.Menu(menu,"Insert picture / PDF…",()=>_=ImportDialogAsync());UI.Menu(menu,"Focus canvas",()=>{inspectorContent.Content=null;inspector.Visibility=Visibility.Collapsed;panel="";});menu.PlacementTarget=Canvas;menu.IsOpen=true;
    }
    private void ExportBoard(Board board){var d=new SaveFileDialog{Filter="Editable EngBoard drawing|*.engboard",FileName=UI.Safe(board.Title)+".engboard"};if(d.ShowDialog(this)==true)Try(()=>File.WriteAllText(d.FileName,BoardCodec.Serialize(board)));}
    public void SetStatus(string text){if(!Dispatcher.CheckAccess()){Dispatcher.BeginInvoke(()=>SetStatus(text));return;}status.Text=text;status.ToolTip=text;}
    private void Try(Action action){try{action();SetStatus("Done");}catch(Exception ex){UI.Error(this,ex);SetStatus(ex.Message);}}
    public void ShowWindow(Window window){Canvas.FinishStroke();window.Owner=this;window.SourceInitialized+=(_,_)=>WindowsTheme.ApplyNative(window);window.Show();}
    private void ShowHelp()=>ShowWindow(new TabletDiagnosticsWindow(Session));
    private async void Keys(object sender,KeyEventArgs e)
    {
        if(e.OriginalSource is TextBox or PasswordBox||e.OriginalSource is DependencyObject d&&FindTextParent(d))return;
        bool control=Keyboard.Modifiers.HasFlag(ModifierKeys.Control);
        if(control){if(editing)Canvas.FinishStroke();switch(e.Key){case Key.N:e.Handled=true;await NewBoardAsync();return;case Key.O:e.Handled=true;await ImportDialogAsync();return;case Key.S:e.Handled=true;await SaveBeforeLeavingAsync();return;case Key.F:e.Handled=true;if(!editing){search.Focus();search.SelectAll();}else ShowPanel("Symbols");return;case Key.Z:if(editing){if(Keyboard.Modifiers.HasFlag(ModifierKeys.Shift))Session.Redo();else Session.Undo();}break;case Key.Y:if(editing)Session.Redo();break;case Key.A:if(editing)Session.SelectAll();break;case Key.C:if(editing)BoardClipboard.Copy(Session);break;case Key.X:if(editing)BoardClipboard.Cut(Session);break;case Key.V:if(editing)Try(Canvas.Paste);break;default:return;}e.Handled=true;return;}
        if(!editing)return;if(e.Key>=Key.D0&&e.Key<=Key.D9){var index=e.Key==Key.D0?9:(int)e.Key-(int)Key.D1;pens.SelectedItem=BrushSettings.PenNames[index];SetTool("Draw");e.Handled=true;return;}
        switch(e.Key){case Key.B:SetTool("Draw");break;case Key.E:SetTool("Eraser");break;case Key.V:SetTool("Select");break;case Key.L:SetTool("Lasso");break;case Key.Delete:Canvas.FinishStroke();Session.DeleteSelection();break;case Key.OemPlus:case Key.Add:Zoom(1.15);break;case Key.OemMinus:case Key.Subtract:Zoom(1/1.15);break;case Key.Escape:Session.PendingSymbolId=null;Session.SelectedIds.Clear();inspectorContent.Content=null;inspector.Visibility=Visibility.Collapsed;panel="";Session.NotifyViewChanged();break;default:return;}e.Handled=true;
    }
    private static bool FindTextParent(DependencyObject child){for(var p=child;p!=null;p=VisualTreeHelper.GetParent(p))if(p is TextBox or PasswordBox)return true;return false;}

}

internal static class UI
{
    public static TextBlock Text(string text,double size=13,bool muted=false){var t=new TextBlock{Text=text,FontSize=size,TextWrapping=TextWrapping.Wrap,Margin=new Thickness(0,3,0,4)};t.SetResourceReference(TextBlock.ForegroundProperty,muted?"MutedBrush":"TextBrush");return t;}
    public static FrameworkElement Spacer(double height)=>new Border{Height=height};
    public static Button Button(object label,Action action,bool accent=false){var b=new Button{Content=label};if(accent)b.SetResourceReference(FrameworkElement.StyleProperty,"AccentButton");b.Click+=(_,_)=>{try{action();}catch(Exception ex){Error(Window.GetWindow(b),ex);}};return b;}
    public static Border Card(UIElement content,double padding=16){var b=new GlassSurface{Child=content,Padding=new Thickness(padding),ShowShadow=padding>0};b.SetResourceReference(FrameworkElement.StyleProperty,"GlassCard");return b;}
    public static void Check(Panel stack,string label,bool value,Action<bool> update){var c=new CheckBox{Content=label,IsChecked=value};c.Checked+=(_,_)=>update(true);c.Unchecked+=(_,_)=>update(false);stack.Children.Add(c);}
    public static void Slider(Panel stack,string label,double min,double max,double value,Action<double> update){var row=new DockPanel();var number=Text(value.ToString("0.##",CultureInfo.InvariantCulture),11,true);DockPanel.SetDock(number,Dock.Right);row.Children.Add(number);row.Children.Add(Text(label,12));stack.Children.Add(row);var s=new Slider{Minimum=min,Maximum=max,Value=Math.Clamp(value,min,max),Margin=new Thickness(0,0,0,8)};s.ValueChanged+=(_,_)=>{number.Text=s.Value.ToString("0.##",CultureInfo.InvariantCulture);update(s.Value);};stack.Children.Add(s);}
    public static void Numeric(Panel stack,string label,double value,Action<double> update){stack.Children.Add(Text(label,12));var input=new TextBox{Text=value.ToString("0.###",CultureInfo.InvariantCulture)};void Apply(){if(double.TryParse(input.Text,NumberStyles.Float,CultureInfo.InvariantCulture,out var n)&&double.IsFinite(n))update(n);else input.Text=value.ToString(CultureInfo.InvariantCulture);}input.LostKeyboardFocus+=(_,_)=>Apply();input.KeyDown+=(_,e)=>{if(e.Key==Key.Enter){Apply();e.Handled=true;}};stack.Children.Add(input);}
    public static void Menu(ContextMenu menu,string label,Action action){var i=new MenuItem{Header=label};i.Click+=(_,_)=>{try{action();}catch(Exception ex){Error(Application.Current.MainWindow,ex);}};menu.Items.Add(i);}
    public static void Error(Window? owner,Exception ex){if(owner!=null)MessageBox.Show(owner,ex.Message,"Please check",MessageBoxButton.OK,MessageBoxImage.Warning);else MessageBox.Show(ex.Message,"Please check");}
    public static string Safe(string text){var s=string.Concat(text.Select(c=>Path.GetInvalidFileNameChars().Contains(c)?'_':c));return s.Length==0?"Drawing":s[..Math.Min(s.Length,120)];}
    public static BitmapSource Bitmap(string path,int width){var bitmap=new BitmapImage();bitmap.BeginInit();bitmap.UriSource=new Uri(path);bitmap.CacheOption=BitmapCacheOption.OnLoad;bitmap.DecodePixelWidth=width;bitmap.EndInit();bitmap.Freeze();return bitmap;}
    public static string? Prompt(Window owner,string title,string label,string initial){var w=new Window{Owner=owner,Title=title,Width=410,SizeToContent=SizeToContent.Height,ResizeMode=ResizeMode.NoResize,WindowStartupLocation=WindowStartupLocation.CenterOwner};var stack=new StackPanel{Margin=new Thickness(22)};stack.Children.Add(Text(label));var input=new TextBox{Text=initial};stack.Children.Add(input);var buttons=new WrapPanel();buttons.Children.Add(Button("Save",()=>w.DialogResult=true,true));buttons.Children.Add(Button("Cancel",()=>w.DialogResult=false));stack.Children.Add(buttons);w.Content=stack;w.Loaded+=(_,_)=>{WindowsTheme.ApplyNative(w);input.Focus();input.SelectAll();};return w.ShowDialog()==true?input.Text:null;}
}

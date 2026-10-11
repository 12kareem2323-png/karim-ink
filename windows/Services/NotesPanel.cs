using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using Microsoft.Win32;
namespace KarimEldamatyWindows;

public sealed class NotesPanel : UserControl
{
    private readonly DrawingSession session;
    private readonly TextBox notes=ServiceUI.Input("",true),notion=ServiceUI.Input(),whiteboard=ServiceUI.Input(),endpoint=ServiceUI.Input(),target=ServiceUI.Input();
    private readonly PasswordBox token=new(){Padding=new Thickness(9),Margin=new Thickness(0,4,0,8)};
    private readonly CheckBox live=ServiceUI.Check("Live one-way send while this panel is visible");
    private readonly TextBlock status=ServiceUI.Text("Ready",12,true),craftStatus=ServiceUI.Text("Set a Craft API connection and one target whiteboard.",12,true);
    private readonly DispatcherTimer debounce=new(){Interval=TimeSpan.FromSeconds(1.2)};
    private readonly Button send;
    private CancellationTokenSource? pending;
    private bool subscribed,updating;
    private Guid sendingBoard;
    public NotesPanel(DrawingSession session)
    {
        this.session=session;MinWidth=280;var stack=new StackPanel{Margin=new Thickness(16)};stack.Children.Add(ServiceUI.Text("Notes & connections",21));
        stack.Children.Add(ServiceUI.Text("Notes",15));notes.MinHeight=150;SpellCheck.SetIsEnabled(notes,true);stack.Children.Add(notes);
        stack.Children.Add(ServiceUI.Text("Notion page URL"));stack.Children.Add(notion);stack.Children.Add(ServiceUI.Button("Open Notion page",()=>Open(notion.Text)));
        stack.Children.Add(ServiceUI.Text("Craft whiteboard page URL"));stack.Children.Add(whiteboard);stack.Children.Add(ServiceUI.Button("Open Craft page",()=>Open(whiteboard.Text)));
        stack.Children.Add(ServiceUI.Button("Save notes and page links",SaveNotes));stack.Children.Add(status);
        var exports=new WrapPanel();exports.Children.Add(ServiceUI.Button("Copy native board link",()=>{var copied=ServiceUI.TryCopyText(CraftExchange.NativeLink(session.Board),out var message);status.Text=copied?"Native drawing link copied. It opens a saved board on a computer with this app installed.":message;}));exports.Children.Add(ServiceUI.Button("Export editable Excalidraw",ExportExcalidraw));exports.Children.Add(ServiceUI.Button("Export Notion HTML",ExportHtml));stack.Children.Add(exports);
        stack.Children.Add(ServiceUI.Text("Excalidraw keeps basic objects editable; complex diagrams use image assets. The HTML copy contains a background image plus editable new ink. Export its new ink as JSON to keep it; it does not update the native board automatically.",11,true));
        stack.Children.Add(ServiceUI.Text("Craft one-way send",18));stack.Children.Add(ServiceUI.Text("Only this drawing's imported objects are reconciled. Other Craft objects stay intact. Direct Send supports basic ink, shapes, text and dimensions; use Excalidraw export for images and complex diagrams.",12,true));
        stack.Children.Add(ServiceUI.Text("Craft API URL from Imagine"));stack.Children.Add(endpoint);stack.Children.Add(ServiceUI.Text("Optional bearer token"));stack.Children.Add(token);stack.Children.Add(ServiceUI.Text("Target whiteboard block ID"));stack.Children.Add(target);
        stack.Children.Add(ServiceUI.Button("Save Craft connection",SaveConnection));stack.Children.Add(ServiceUI.Button("Remove saved Craft connection",()=>{try{Stop();CredentialStore.Delete("craft-connection");CredentialStore.Delete("craft-target");endpoint.Clear();target.Clear();token.Clear();craftStatus.Text="Craft connection removed.";}catch(Exception ex){craftStatus.Text=ex.Message;}}));
        stack.Children.Add(live);send=ServiceUI.Button("Send drawing to Craft",()=>_=SendAsync());stack.Children.Add(send);stack.Children.Add(ServiceUI.Button("Cancel Craft send",Stop));stack.Children.Add(craftStatus);
        stack.Children.Add(ServiceUI.Text("Live send is off when this panel opens. Enabling it sends changes to the chosen Craft whiteboard while this panel stays visible. Leaving the panel stops scheduled work. An interrupted request may already have reached Craft; Send again to reconcile.",11,true));
        Content=new ScrollViewer{Content=stack,VerticalScrollBarVisibility=ScrollBarVisibility.Auto};SetResourceReference(BackgroundProperty,"SurfaceBrush");
        IsVisibleChanged += (_,_) => { if(!IsVisible) Stop(); };
        try{var saved=CraftConnection.Load();endpoint.Text=saved.Endpoint;target.Text=CredentialStore.Read("craft-target")??"";craftStatus.Text="Saved connection ready. Send only updates the chosen whiteboard.";}catch(InvalidOperationException){}catch(Exception ex){craftStatus.Text=ex.Message;}
        Loaded+=(_,_)=>{if(!subscribed){session.Changed+=OnBoardChanged;subscribed=true;}RefreshBoardFields();};Unloaded+=(_,_)=>{Stop();if(subscribed){session.Changed-=OnBoardChanged;subscribed=false;}};
        notes.LostKeyboardFocus+=(_,_)=>SaveNotes();notion.LostKeyboardFocus+=(_,_)=>SaveNotes();whiteboard.LostKeyboardFocus+=(_,_)=>SaveNotes();
        live.Checked+=(_,_)=>{if(!IsVisible)return;try{_=CraftConnection.Load();if(!CraftConnection.ValidIdentifier(target.Text.Trim()))throw new ArgumentException("Choose a target whiteboard ID first.");craftStatus.Text="Live send enabled for this visible panel.";Schedule();}catch(Exception ex){live.IsChecked=false;craftStatus.Text=ex.Message;}};live.Unchecked+=(_,_)=>debounce.Stop();
        debounce.Tick+=(_,_)=>{debounce.Stop();if(live.IsChecked==true&&IsVisible&&pending==null)_=SendAsync();};RefreshBoardFields();
    }
    private void RefreshBoardFields(){updating=true;try{if(!notes.IsKeyboardFocusWithin)notes.Text=session.Board.Notes;if(!notion.IsKeyboardFocusWithin)notion.Text=session.Board.NotionURL;if(!whiteboard.IsKeyboardFocusWithin)whiteboard.Text=session.Board.WhiteboardURL;}finally{updating=false;}}
    private void SaveNotes()
    {
        if(updating)return;var b=session.Board;if(b.Notes==notes.Text&&b.NotionURL==notion.Text&&b.WhiteboardURL==whiteboard.Text)return;
        if(notes.Text.Length>100000){status.Text="Keep notes below 100,000 characters.";return;}
        session.Checkpoint();b.Notes=notes.Text;b.NotionURL=notion.Text.Trim();b.WhiteboardURL=whiteboard.Text.Trim();session.NotifyChanged();status.Text="Notes and page links saved in the native drawing.";
    }
    private void Open(string value){try{SaveNotes();ServiceUI.OpenWeb(value);}catch(Exception ex){status.Text=ex.Message;}}
    private void SaveConnection()
    {
        try{var connection=new CraftConnection{Endpoint=endpoint.Text.Trim(),BearerToken=token.Password.Trim()};if(token.Password.Length==0){try{var previous=CraftConnection.Load();if(previous.Endpoint.TrimEnd('/')==connection.Endpoint.TrimEnd('/'))connection.BearerToken=previous.BearerToken;}catch(InvalidOperationException){}}
            if(!CraftConnection.ValidIdentifier(target.Text.Trim()))throw new ArgumentException("Enter the block ID of one target whiteboard.");connection.Save();CredentialStore.Save("craft-target",target.Text.Trim());token.Clear();craftStatus.Text="Craft connection saved with Windows per-user encryption. Ready for Send.";}
        catch(Exception ex){craftStatus.Text=ex.Message;}
    }
    private void OnBoardChanged(){RefreshBoardFields();if(pending!=null&&session.Board.Id!=sendingBoard)Stop();if(live.IsChecked==true&&IsVisible)Schedule();}
    private void Schedule(){debounce.Stop();debounce.Start();}
    private async Task SendAsync()
    {
        if(pending!=null)return;SaveNotes();pending=new CancellationTokenSource();var operation=pending;send.IsEnabled=false;sendingBoard=session.Board.Id;var revision=session.Revision;craftStatus.Text="Updating the chosen Craft whiteboard…";
        try{var count=await new CraftClient(CraftConnection.Load()).SendAsync(BoardCodec.Clone(session.Board),target.Text.Trim(),operation.Token);craftStatus.Text="Verified "+count+" imported objects in Craft.";}
        catch(OperationCanceledException){craftStatus.Text="Craft send stopped. Send again to reconcile any accepted changes.";}
        catch(Exception ex){live.IsChecked=false;craftStatus.Text=ex.Message;}
        finally{operation.Dispose();pending=null;send.IsEnabled=true;if(live.IsChecked==true&&IsVisible&&session.Revision!=revision)Schedule();}
    }
    private void Stop(){live.IsChecked=false;debounce.Stop();pending?.Cancel();}
    private void ExportExcalidraw(){try{SaveNotes();var dialog=new SaveFileDialog{Filter="Excalidraw whiteboard|*.excalidraw",FileName=ServiceUI.SafeFileName(session.Board.Title)+".excalidraw"};if(dialog.ShowDialog()==true){CraftExchange.ExportExcalidraw(session.Board,dialog.FileName);status.Text="Editable whiteboard export saved.";}}catch(Exception ex){status.Text=ex.Message;}}
    private void ExportHtml(){try{SaveNotes();var dialog=new SaveFileDialog{Filter="HTML drawing copy|*.html",FileName=ServiceUI.SafeFileName(session.Board.Title)+" - Notion.html"};if(dialog.ShowDialog()==true){NotionHTMLExport.ExportNotionHtml(session.Board,dialog.FileName,BoardExport.RenderPNG(session.Board));status.Text="Offline HTML drawing copy saved. Host it separately if you want a Notion embed.";}}catch(Exception ex){status.Text=ex.Message;}}
}

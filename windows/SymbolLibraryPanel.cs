using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
namespace KarimEldamatyWindows;

/// Only visible rows decode thumbnails. Searching never constructs 380 image controls.
public sealed class SymbolLibraryPanel : Grid
{
    private readonly List<SymbolEntry> definitions;
    private readonly ListBox list=new(){ BorderThickness=new Thickness(0),Background=Brushes.Transparent,HorizontalContentAlignment=HorizontalAlignment.Stretch };
    private readonly TextBox query=new(){ToolTip="Search symbols"};
    private readonly ComboBox categories=new();
    private readonly DispatcherTimer filterDelay=new(){Interval=TimeSpan.FromMilliseconds(150)};
    private Point dragStart;
    private bool dragging;
    public SymbolLibraryPanel(DrawingSession session)
    {
        Margin=new Thickness(14);
        RowDefinitions.Add(new(){Height=GridLength.Auto});RowDefinitions.Add(new(){Height=new GridLength(1,GridUnitType.Star)});
        definitions=JsonSerializer.Deserialize<List<SymbolEntry>>(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"Resources","SymbolCatalog.json")),new JsonSerializerOptions{PropertyNameCaseInsensitive=true})??[];
        var header=new StackPanel();header.Children.Add(UI.Text("Engineering library",21));header.Children.Add(UI.Text($"{definitions.Count} diagrams · choose and place, or drag",11,true));header.Children.Add(query);header.Children.Add(categories);Children.Add(header);
        categories.ItemsSource=new[]{"All categories"}.Concat(definitions.Select(d=>d.Category).Distinct().Order()).ToArray();categories.SelectedIndex=0;
        VirtualizingPanel.SetIsVirtualizing(list,true);VirtualizingPanel.SetVirtualizationMode(list,VirtualizationMode.Recycling);ScrollViewer.SetCanContentScroll(list,true);
        list.ItemTemplate=new DataTemplate(typeof(SymbolEntry)){VisualTree=new FrameworkElementFactory(typeof(SymbolLibraryRow))};
        SetRow(list,1);Children.Add(list);
        void Filter(){filterDelay.Stop();var text=query.Text.Trim();list.ItemsSource=definitions.Where(d=>(categories.SelectedIndex==0||d.Category==(string?)categories.SelectedItem)&&(d.Name+" "+d.Category+" "+string.Join(' ',d.Keywords)).Contains(text,StringComparison.OrdinalIgnoreCase)).ToArray();}
        filterDelay.Tick+=(_,_)=>Filter();query.TextChanged+=(_,_)=>{filterDelay.Stop();filterDelay.Start();};categories.SelectionChanged+=(_,_)=>Filter();Unloaded+=(_,_)=>filterDelay.Stop();
        list.SelectionChanged+=(_,_)=>{if(list.SelectedItem is SymbolEntry definition){session.PendingSymbolId=definition.Id;session.Tool="Draw";session.SelectedIds.Clear();session.NotifyViewChanged();session.Status("Click the canvas to place "+definition.Name);}};
        list.PreviewMouseLeftButtonDown+=(_,e)=>dragStart=e.GetPosition(list);
        list.PreviewMouseMove+=(_,e)=>{var distance=e.GetPosition(list)-dragStart;if(dragging||e.LeftButton!=MouseButtonState.Pressed||Math.Abs(distance.X)<SystemParameters.MinimumHorizontalDragDistance&&Math.Abs(distance.Y)<SystemParameters.MinimumVerticalDragDistance)return;if(list.SelectedItem is not SymbolEntry d)return;try{dragging=true;DragDrop.DoDragDrop(list,new DataObject("EngBoardSymbol",d.Id),DragDropEffects.Copy);}finally{dragging=false;}};
        Filter();
    }
}
public sealed class SymbolLibraryRow : DockPanel
{
    private readonly Image image=new(){Width=84,Height=64,Stretch=Stretch.Uniform};
    private readonly TextBlock name=UI.Text("",12),category=UI.Text("",10,true);
    public SymbolLibraryRow()
    {
        Margin=new Thickness(0,6,0,6);
        Children.Add(new Border{Background=Brushes.White,CornerRadius=new CornerRadius(8),Child=image,Margin=new Thickness(0,0,10,0)});
        var caption=new StackPanel{VerticalAlignment=VerticalAlignment.Center};caption.Children.Add(name);caption.Children.Add(category);Children.Add(caption);
        DataContextChanged+=(_,_)=>{if(IsLoaded)Refresh();};Loaded+=(_,_)=>Refresh();Unloaded+=(_,_)=>image.Source=null;
    }
    private void Refresh(){if(DataContext is not SymbolEntry d)return;name.Text=d.Name;category.Text=d.Category;try{image.Source=UI.Bitmap(Path.Combine(AppContext.BaseDirectory,"Resources","Symbols",d.Id+".png"),100);}catch(IOException){image.Source=null;}}
}

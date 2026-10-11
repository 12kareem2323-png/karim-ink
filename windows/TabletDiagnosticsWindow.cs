using System.Diagnostics;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
namespace KarimEldamatyWindows;

/// A disposable scratchpad tests the packets delivered by any Windows Ink tablet driver.
public sealed class TabletDiagnosticsWindow : Window
{
    private readonly DrawingSession test=new();
    private readonly BoardCanvas canvas;
    private readonly TextBlock telemetry=UI.Text("Move your pen over the scratchpad, then draw lightly and firmly.",12);
    private long lastUpdate;
    private double? minimumPressure,maximumPressure;
    private long pressureSamples;
    public TabletDiagnosticsWindow(DrawingSession source)
    {
        SetResourceReference(StyleProperty, typeof(Window));
        Title="Tablet test · SketchGlide";Width=920;Height=720;MinWidth=700;MinHeight=560;WindowStartupLocation=WindowStartupLocation.CenterOwner;
        test.Pen=source.Pen;test.Settings=BoardCodec.Clone(source.Settings);test.Color=source.Color;test.ActivationPressure=source.ActivationPressure;test.BarrelButtonAction=source.BarrelButtonAction;
        test.SetBoard(new(){Title="Temporary tablet scratchpad",Width=1200,Height=700,Background="Dot grid"});canvas=new(){Session=test};
        var layout=new Grid{Margin=new Thickness(18)};layout.RowDefinitions.Add(new(){Height=GridLength.Auto});layout.RowDefinitions.Add(new(){Height=new GridLength(1,GridUnitType.Star)});layout.RowDefinitions.Add(new(){Height=GridLength.Auto});
        var header=new StackPanel();header.Children.Add(UI.Text("Your tablet, your pen",24));header.Children.Add(UI.Text("Wacom, Huion, XP-Pen, Xencelabs and other brands use their Windows Ink driver. Install the maker’s current driver and enable Windows Ink for this app. Features appear when the driver supplies them.",12,true));
        var controls=new WrapPanel();var pen=new ComboBox{ItemsSource=BrushSettings.PenNames,SelectedItem=test.Pen,Width=170};pen.SelectionChanged+=(_,_)=>{canvas.FinishStroke();test.SetPen(pen.SelectedItem as string??"Technical Fineliner");};controls.Children.Add(pen);
        controls.Children.Add(UI.Button("Clear test drawing",()=>{canvas.FinishStroke();test.SetBoard(new(){Title="Temporary tablet scratchpad",Width=1200,Height=700,Background="Dot grid"});}));
        controls.Children.Add(UI.Button("Save input report",SaveReport));header.Children.Add(controls);layout.Children.Add(header);
        var surface=UI.Card(canvas,0);surface.Margin=new Thickness(0,12,0,12);Grid.SetRow(surface,1);layout.Children.Add(surface);
        var footer=new StackPanel();footer.Children.Add(telemetry);footer.Children.Add(UI.Text("Test: light/heavy pressure · pen tilt · hover · side button · inverted eraser. This scratchpad is temporary. Shortcut remotes can map 1–0 to pens, B/E/V/L to tools, Ctrl+C/X/V, Ctrl+Z/Y and wheel to zoom. Space + drag pans.",11,true));Grid.SetRow(footer,2);layout.Children.Add(footer);Content=layout;
        test.InputChanged+=Update;Loaded+=(_,_)=>{canvas.FitBoard();canvas.Focus();};Closed+=(_,_)=>test.InputChanged-=Update;SourceInitialized+=(_,_)=>WindowsTheme.ApplyNative(this);
    }
    private void Update()
    {
        if(test.LiveRawPressure is {} raw){minimumPressure=Math.Min(minimumPressure??raw,raw);maximumPressure=Math.Max(maximumPressure??raw,raw);pressureSamples++;}
        var now=Stopwatch.GetTimestamp();if((now-lastUpdate)/(double)Stopwatch.Frequency<.1)return;lastUpdate=now;
        var c=test.InputCapabilities;
        telemetry.Text=$"{c.DeviceName}  {c.PenName}\nPressure: {(test.LiveRawPressure is {} p?p.ToString("P0"):"unavailable")} · range {(minimumPressure is {} min?min.ToString("P0"):"—")}–{(maximumPressure is {} max?max.ToString("P0"):"—")} · tilt X/Y {(c.TiltXSupported?"yes":"no")}/{(c.TiltYSupported?"yes":"no")}\nHover reported: {c.HoverSupported} · eraser observed: {c.EraserObserved} · side button observed: {c.BarrelButtonObserved} · delivered samples: {c.DeliveredSamples}";
    }
    private void SaveReport()
    {
        var dialog=new SaveFileDialog{Filter="Input report|*.json",FileName="Karim-tablet-input-report.json"};if(dialog.ShowDialog(this)!=true)return;
        var report=new{date=DateTimeOffset.Now,os=Environment.OSVersion.ToString(),device=test.InputCapabilities,minimumPressure,maximumPressure,pressureSamples,
            physicalPenPacketsObserved=test.InputCapabilities.RuntimeDeviceId.Length>0&&test.InputCapabilities.DeliveredSamples>0,
            scope="Driver capabilities and observed Windows pen packets only. Unobserved features and raw vendor pressure levels are not certified."};
        File.WriteAllText(dialog.FileName,JsonSerializer.Serialize(report,new JsonSerializerOptions{WriteIndented=true}));
    }
}

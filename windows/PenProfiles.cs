using System.Text.Json;
using System.Windows.Threading;
namespace KarimEldamatyWindows;

/// Per-device app calibration. A device key comes from the installed Windows Ink driver.
internal sealed class PenProfiles
{
    private readonly Dictionary<string,PenProfileData> profiles=[];
    private readonly string path=Path.Combine(App.TestDataDirectory??Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"KarimEldamaty"),"pen-profiles.json");
    private readonly DispatcherTimer debounce=new(){Interval=TimeSpan.FromMilliseconds(600)};
    public PenProfiles(){try{if(File.Exists(path)&&new FileInfo(path).Length<2*1024*1024){var loaded=JsonSerializer.Deserialize<Dictionary<string,PenProfileData>>(File.ReadAllText(path));if(loaded!=null)foreach(var pair in loaded.Take(200))if(pair.Value is not null&&pair.Key.Length<400){pair.Value.Normalize();profiles[pair.Key]=pair.Value;}}}catch(Exception e)when(e is IOException or JsonException or UnauthorizedAccessException){}debounce.Tick+=(_,_)=>{debounce.Stop();Flush();};}
    private static string Key(DrawingSession s,string? device)=>(device??"mouse")+"/"+s.Pen;
    public void SaveProfile(DrawingSession s,string? device){profiles[Key(s,device)]=new(){Settings=BoardCodec.Clone(s.Settings),Color=new InkColor(s.Color.R,s.Color.G,s.Color.B,s.Color.A),Activation=s.ActivationPressure,Smoothing=s.Smoothing,BarrelButtonAction=s.BarrelButtonAction,EraserMode=s.EraserMode,EraserRadius=s.EraserRadius};debounce.Stop();debounce.Start();}
    public void LoadProfile(DrawingSession s,string? device){if(!profiles.TryGetValue(Key(s,device),out var p))return;p.Normalize();s.Settings=BoardCodec.Clone(p.Settings);s.Color=BoardCodec.Clone(p.Color);s.ActivationPressure=p.Activation;s.Smoothing=p.Smoothing;s.BarrelButtonAction=p.BarrelButtonAction;s.EraserMode=p.EraserMode;s.EraserRadius=p.EraserRadius;}
    public void Flush(){debounce.Stop();try{Directory.CreateDirectory(Path.GetDirectoryName(path)!);var temp=path+"."+Guid.NewGuid().ToString("N")+".tmp";File.WriteAllText(temp,JsonSerializer.Serialize(profiles));File.Move(temp,path,true);}catch(Exception e)when(e is IOException or UnauthorizedAccessException){ApplicationStatus(e.Message);}}
    private static void ApplicationStatus(string message){if(System.Windows.Application.Current?.MainWindow is MainWindow w)w.SetStatus("Pen profile could not be saved: "+message);}
}

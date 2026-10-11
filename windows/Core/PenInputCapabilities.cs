using System.Security.Cryptography;
using System.Text;
namespace KarimEldamatyWindows;
public sealed class PenInputCapabilities
{
    public string DeviceName {get;set;}="Mouse";
    public string PenName {get;set;}="";
    public string DeviceKey {get;set;}="mouse";
    public string RuntimeDeviceId {get;set;}="";
    public string IdentitySource {get;set;}="Mouse";
    public bool PressureSupported {get;set;}
    public bool TiltXSupported {get;set;}
    public bool TiltYSupported {get;set;}
    public bool EraserObserved {get;set;}
    public bool BarrelButtonObserved {get;set;}
    public bool PhysicalPenIdentityAvailable {get;set;}
    public bool HoverSupported {get;set;}
    public long DeliveredSamples {get;set;}
    public static string ProfileKey(string? productId,string? tabletName,string? penName)
    {
        static string Normal(string? value)=>string.Concat((value??"").Normalize(NormalizationForm.FormKC).Where(c=>!char.IsControl(c))).Trim().ToUpperInvariant();
        var identity=Normal(productId)+"\n"+Normal(tabletName)+"\n"+Normal(penName);
        return "ink:"+Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(identity)))[..24];
    }
}
public sealed class PenProfileData
{
    public BrushSettings Settings {get;set;}=new();
    public InkColor Color {get;set;}=InkColor.Graphite;
    public double Activation {get;set;}=.01;
    public double Smoothing {get;set;}=.45;
    public string BarrelButtonAction {get;set;}="Pan";
    public string EraserMode {get;set;}="Stroke";
    public double EraserRadius {get;set;}=20;
    public void Normalize()
    {
        static double Finite(double x,double min,double max,double fallback)=>double.IsFinite(x)?Math.Clamp(x,min,max):fallback;
        Settings??=new();Color??=InkColor.Graphite;
        Settings.MinWidth=Finite(Settings.MinWidth,.15,80,1);Settings.MaxWidth=Finite(Settings.MaxWidth,Settings.MinWidth,80,Math.Max(Settings.MinWidth,4));Settings.PressureGamma=Finite(Settings.PressureGamma,.15,4,1);Settings.Opacity=Finite(Settings.Opacity,0,1,1);Settings.MinOpacity=Finite(Settings.MinOpacity,0,1,.35);Settings.MaxOpacity=Finite(Settings.MaxOpacity,Settings.MinOpacity,1,1);Settings.TextureScale=Finite(Settings.TextureScale,.1,5,1);if(!BrushSettings.PencilGrades.Contains(Settings.PencilGrade))Settings.PencilGrade="HB";
        Color.R=Finite(Color.R,0,1,.14);Color.G=Finite(Color.G,0,1,.20);Color.B=Finite(Color.B,0,1,.28);Color.A=Finite(Color.A,0,1,1);Activation=Finite(Activation,0,.95,.01);Smoothing=Finite(Smoothing,0,.85,.45);EraserRadius=Finite(EraserRadius,1,1000,20);
        if(BarrelButtonAction is not ("Pan" or "Context menu" or "None"))BarrelButtonAction="Pan";if(EraserMode is not ("Stroke" or "Partial"))EraserMode="Stroke";
    }
}

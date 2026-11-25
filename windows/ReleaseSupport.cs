using System.Reflection;

namespace KarimEldamatyWindows;
internal static class ReleaseSupport
{
    public const string Repository = "12kareem2323-png/karim-ink";
    public const string Source = "https://github.com/" + Repository + "/tree/velin/windows-x64";
    public const string Releases = "https://github.com/" + Repository + "/releases";
    public static string Version { get; } =
        typeof(ReleaseSupport).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()!
            .InformationalVersion.Split('+')[0];
    public const string Website = "https://karim-ink.stonyvale1.chatgpt.site/";
    public const string Feedback = "https://github.com/12kareem2323-png/karim-ink/issues/new/choose";
    public const string PayPal = "https://paypal.me/KEldamaty";
}

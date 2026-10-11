using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
namespace KarimEldamatyWindows;
internal static class ServiceUI
{
    public static TextBlock Text(string value, double size = 13, bool muted = false)
    { var v = new TextBlock { Text = value, FontSize = size, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 8) }; v.SetResourceReference(TextBlock.ForegroundProperty, muted ? "MutedBrush" : "TextBrush"); return v; }
    public static Button Button(string label, Action action)
    { var v = new Button { Content = label, Padding = new Thickness(12, 7, 12, 7), Margin = new Thickness(0, 4, 7, 4) }; v.Click += (_, _) => action(); return v; }
    public static TextBox Input(string value = "", bool multiline = false)
    { var v = new TextBox { Text = value, Padding = new Thickness(9), Margin = new Thickness(0, 4, 0, 8), AcceptsReturn = multiline, TextWrapping = multiline ? TextWrapping.Wrap : TextWrapping.NoWrap, MinHeight = multiline ? 100 : 34, VerticalScrollBarVisibility = multiline ? ScrollBarVisibility.Auto : ScrollBarVisibility.Hidden }; v.SetResourceReference(TextBox.BackgroundProperty, "CardBrush"); v.SetResourceReference(TextBox.ForegroundProperty, "TextBrush"); v.SetResourceReference(TextBox.BorderBrushProperty, "BorderBrush"); return v; }
    public static CheckBox Check(string label) { var v = new CheckBox { Content = label, Margin = new Thickness(0, 7, 0, 7) }; v.SetResourceReference(CheckBox.ForegroundProperty, "TextBrush"); return v; }
    public static bool TryCopyText(string value,out string message)
    {
        try { Clipboard.SetText(value,TextDataFormat.UnicodeText);message="Copied to the Windows clipboard.";return true; }
        catch(System.Runtime.InteropServices.ExternalException) { message="The Windows clipboard is busy. Try Copy again.";return false; }
    }
    public static string SafeFileName(string value) { foreach (var c in System.IO.Path.GetInvalidFileNameChars()) value = value.Replace(c, '_'); return string.IsNullOrWhiteSpace(value) ? "Drawing" : value; }
    public static void OpenWeb(string value)
    {
        if (!Uri.TryCreate(value.Trim(), UriKind.Absolute, out var uri) || uri.Scheme is not ("https" or "http") || uri.UserInfo.Length > 0) throw new ArgumentException("Enter a valid https web link.");
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true });
    }
}

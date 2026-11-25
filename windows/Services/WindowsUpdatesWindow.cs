using System.Windows;
using System.Windows.Controls;

namespace KarimEldamatyWindows;

internal sealed class WindowsUpdatesWindow : Window
{
    public WindowsUpdatesWindow()
    {
        Title = "Velin updates";
        Width = 440;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var installed = WindowsUpdates.ParseTag(WindowsUpdates.TagPrefix + ReleaseSupport.Version)!;
        var stack = new StackPanel { Margin = new Thickness(18) };
        Content = stack;
        stack.Children.Add(UI.Text($"Velin {installed.Label}", 22));
        stack.Children.Add(UI.Text("Windows x64 · Made by Karim Eldamaty", 12, true));
        var result = UI.Text("Check GitHub for a newer Windows release.", 13);
        stack.Children.Add(result);
        var buttons = new WrapPanel();
        stack.Children.Add(buttons);

        WindowsRelease? available = null;
        // The window owns a separate token for each check so closing takes effect during the request.
        CancellationTokenSource? request = null;
        Closed += (_, _) => request?.Cancel();
        var download = UI.Button("Open release ↗", () =>
            ServiceUI.OpenWeb(available?.Page ?? ReleaseSupport.Releases));
        download.Visibility = Visibility.Collapsed;
        var check = new Button { Content = "Check GitHub" };
        check.Click += async (_, _) =>
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(25));
            request = timeout;
            check.IsEnabled = false;
            download.Visibility = Visibility.Collapsed;
            result.Text = "Checking GitHub…";
            try
            {
                available = await WindowsUpdates.CheckAsync(timeout.Token);
                result.Text = available is null ? "No newer Windows build is published." :
                    $"Velin {available.Label} is available. Open its release page to download the ZIP and checksum.";
                download.Visibility = available is null ? Visibility.Collapsed : Visibility.Visible;
            }
            catch (Exception ex) when (ex is System.Net.Http.HttpRequestException or System.Text.Json.JsonException
                or System.IO.IOException or OperationCanceledException or InvalidOperationException or KeyNotFoundException)
            {
                result.Text = "GitHub could not be checked. Try again or open the releases page.";
            }
            finally
            {
                request = null;
                check.IsEnabled = true;
            }
        };
        buttons.Children.Add(check);
        buttons.Children.Add(download);
        buttons.Children.Add(UI.Button("All releases ↗", () => ServiceUI.OpenWeb(ReleaseSupport.Releases)));
    }
}

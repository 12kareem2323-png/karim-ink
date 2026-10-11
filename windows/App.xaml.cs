using System.IO.Pipes;
using System.Security.Principal;
using System.Windows;

namespace KarimEldamatyWindows;

public partial class App : Application
{
    public static string? TestDataDirectory { get; private set; }
    private Mutex? _instance;
    private CancellationTokenSource _stop = new();
    private string _pipeName = "";
    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        bool checking = e.Args.FirstOrDefault() == "--self-test";
        if(checking)TestDataDirectory=Path.Combine(Path.GetTempPath(),"Karim-Windows-SelfTest-"+Guid.NewGuid().ToString("N"));
        WindowsTheme.Load();
        var user = WindowsIdentity.GetCurrent().User?.Value ?? Environment.UserName;
        _pipeName = "KarimEldamaty-" + user;
        _instance = new Mutex(true,"Local\\" + _pipeName,out bool created);
        if (!created && !e.Args.Contains("--self-test"))
        {
            try { using var pipe = new NamedPipeClientStream(".",_pipeName,PipeDirection.Out,PipeOptions.CurrentUserOnly); await pipe.ConnectAsync(3000); using var writer = new StreamWriter(pipe); await writer.WriteLineAsync(e.Args.FirstOrDefault() ?? "activate"); await writer.FlushAsync(); } catch (Exception ex) when(ex is IOException or TimeoutException) { MessageBox.Show("Another copy is still starting. Open it from the taskbar.","SketchGlide"); }
            Shutdown(); return;
        }
        var isolation = checking ? Path.Combine(TestDataDirectory!,"Boards") : null;
        var window = new MainWindow(isolation); MainWindow = window; window.Show();
        window.SourceInitialized += (_,_) => WindowsTheme.ApplyNative(window);
        WindowsTheme.ApplyNative(window);
        await window.InitializeAsync();
        if (e.Args.Length > 0 && e.Args[0] != "--self-test") await window.OpenArgumentAsync(e.Args[0]);
        if (e.Args.Length > 0 && e.Args[0] == "--self-test")
        {
            try { await WindowsSelfTest.RunAsync(window,e.Args.ElementAtOrDefault(1)); Shutdown(0); } catch (Exception ex) { Console.Error.WriteLine(ex); Shutdown(1); }
            return;
        }
        _ = ListenAsync(window);
    }
    private async Task ListenAsync(MainWindow window)
    {
        while (!_stop.IsCancellationRequested)
        {
            try
            {
                using var pipe = new NamedPipeServerStream(_pipeName,PipeDirection.In,1,PipeTransmissionMode.Byte,PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                await pipe.WaitForConnectionAsync(_stop.Token);
                using var reader = new StreamReader(pipe); var request = await reader.ReadLineAsync(_stop.Token);
                if (request is { Length: < 4096 }) await Dispatcher.InvokeAsync(async () => { window.Show(); if (window.WindowState == WindowState.Minimized) window.WindowState = WindowState.Normal; window.Activate(); if (request != "activate") await window.OpenArgumentAsync(request); }).Task.Unwrap();
            }
            catch (OperationCanceledException) { break; }
            catch (IOException) { await Task.Delay(200,_stop.Token); }
        }
    }
    protected override void OnExit(ExitEventArgs e) { _stop.Cancel(); _instance?.Dispose(); base.OnExit(e); }
}

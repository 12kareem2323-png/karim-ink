using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Win32;

namespace KarimEldamatyWindows;

public static class WindowsTheme
{
    public static string Mode { get; private set; } = "System";
    public static string GlassMaterial { get; private set; } = "Balanced";
    public static bool Dark { get; private set; }
    public static bool ReduceTransparency { get; private set; }
    public static bool GlassEffectsEnabled { get; private set; }
    public static string? PreferenceSaveError { get; private set; }
    public static event Action? Changed;
    private const int DarkModeAttribute = 20, CornerAttribute = 33, BackdropAttribute = 38;
    private const int SettingChanged = 0x001A, ThemeChanged = 0x031A, CompositionChanged = 0x031E;
    private static readonly ConditionalWeakTable<Window, NativeWindowState> Windows = new();
    private static Dictionary<string, string> _preferences = [];
    private static bool _loaded;
    private static DispatcherOperation? _pendingApply;
    private static Brush _nativeTint = Brushes.Transparent, _fallback = Brushes.White;
    private static GlassPolicy _policy;
    private static string? _paletteSignature;
    private static int _paletteVersion;
    private static string FilePath => Path.Combine(App.TestDataDirectory ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "KarimEldamaty"), "appearance.json");

    public static void Load()
    {
        if (_loaded) return;
        _loaded = true;
        try
        {
            if (new FileInfo(FilePath) is { Exists: true, Length: <= 65536 })
                _preferences = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(FilePath)) ?? [];
            Mode = NormalizeMode(_preferences.GetValueOrDefault("mode"));
            GlassMaterial = NormalizeMaterial(_preferences.GetValueOrDefault("glassMaterial"));
            ReduceTransparency = _preferences.GetValueOrDefault("reduceTransparency") == "true";
        }
        catch (Exception error) when (error is IOException or JsonException or UnauthorizedAccessException) { }
        Apply();
        SystemParameters.StaticPropertyChanged += OnSystemChanged;
        SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
        Application.Current.Exit += (_, _) =>
        {
            SystemParameters.StaticPropertyChanged -= OnSystemChanged;
            SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
        };
        // Keep the native caption, resize border, Snap Layouts and taskbar behaviour.
        EventManager.RegisterClassHandler(typeof(Window), FrameworkElement.LoadedEvent,
            new RoutedEventHandler((sender, _) => { if (sender is Window window) ApplyNative(window); }));
    }
    private static string NormalizeMode(string? mode) => mode is "Light" or "Dark" ? mode : "System";
    private static string NormalizeMaterial(string? mode) => mode is "Frosted" or "Solid" ? mode : "Balanced";
    private static void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs args) => QueueApply();
    private static void OnSystemChanged(object? sender, PropertyChangedEventArgs args) => QueueApply();
    private static void QueueApply()
    {
        var dispatcher = Application.Current?.Dispatcher;
        if (dispatcher == null || dispatcher.HasShutdownStarted) return;
        // Multiple OS notifications are common; coalesce them into one palette update.
        dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(() =>
        {
            if (_pendingApply?.Status == DispatcherOperationStatus.Pending) return;
            _pendingApply = dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(() => { _pendingApply = null; Apply(); }));
        }));
    }
    public static void SetMode(string mode) { Mode = NormalizeMode(mode); Save(); Apply(); }
    public static void SetGlassMaterial(string material) { GlassMaterial = NormalizeMaterial(material); Save(); Apply(); }
    public static void SetReduceTransparency(bool reduced) { ReduceTransparency = reduced; Save(); Apply(); }
    public static void Toggle() => SetMode(Dark ? "Light" : "Dark");
    private static void Save()
    {
        _preferences["mode"] = Mode;
        _preferences["glassMaterial"] = GlassMaterial;
        _preferences["reduceTransparency"] = ReduceTransparency ? "true" : "false";
        string temporary = FilePath + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(temporary, JsonSerializer.Serialize(_preferences));
            File.Move(temporary, FilePath, true);
            PreferenceSaveError = null;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        { PreferenceSaveError = "Appearance works for this session, but its settings could not be saved."; }
        finally { try { if (File.Exists(temporary)) File.Delete(temporary); } catch (IOException) { } catch (UnauthorizedAccessException) { } }
    }

    public static void Apply()
    {
        if (!Application.Current.Dispatcher.CheckAccess()) { QueueApply(); return; }
        Dark = Mode == "Dark" || Mode == "System" && ReadPersonalization("AppsUseLightTheme", 1) == 0;
        var signature = string.Join("|", Mode, Dark, GlassMaterial, ReduceTransparency, SystemParameters.HighContrast,
            ReadPersonalization("EnableTransparency", 1), SystemParameters.IsRemoteSession,
            Environment.OSVersion.Version.Build, RenderCapability.Tier >> 16);
        if (_paletteSignature == signature) return;
        _paletteSignature = signature;
        _paletteVersion++;
        _policy = GlassPolicy.Evaluate(GlassMaterial, ReduceTransparency, SystemParameters.HighContrast,
            ReadPersonalization("EnableTransparency", 1) != 0, SystemParameters.IsRemoteSession,
            Environment.OSVersion.Version.Build, RenderCapability.Tier >> 16);
        GlassEffectsEnabled = _policy.EffectsEnabled;
        var resources = Application.Current.Resources;
        if (SystemParameters.HighContrast)
        {
            resources["TextBrush"] = SystemColors.WindowTextBrush;
            resources["MutedBrush"] = SystemColors.WindowTextBrush;
            resources["SurfaceBrush"] = SystemColors.WindowBrush;
            resources["CardBrush"] = SystemColors.WindowBrush;
            resources["AccentBrush"] = SystemColors.HighlightBrush;
            resources["AccentTextBrush"] = SystemColors.HighlightTextBrush;
            resources["BorderBrush"] = SystemColors.WindowTextBrush;
            resources["SpecularBrush"] = Brushes.Transparent;
            _nativeTint = Brushes.Transparent;
            _fallback = SystemColors.WindowBrush;
        }
        else
        {
            resources["TextBrush"] = Solid(Dark ? "#EFF4FA" : "#243347");
            resources["MutedBrush"] = Solid(Dark ? "#ADBCCB" : "#52677B");
            resources["SurfaceBrush"] = Solid(Dark ? "#222831" : "#F0F5F7");
            resources["AccentBrush"] = Solid(Dark ? "#55D9C7" : "#087E72");
            resources["AccentTextBrush"] = Solid(Dark ? "#102B2A" : "#FFFFFF");
            resources["CardBrush"] = GlassEffectsEnabled
                ? Gradient(Dark ? ["#DE34404B", "#BD29333D", "#D3303B48"] : ["#EDFFFFFF", "#CCF8FDFF", "#E3FFFFFF"])
                : Solid(Dark ? "#303841" : "#FFFFFF");
            resources["BorderBrush"] = GlassEffectsEnabled
                ? Gradient(Dark ? ["#75E4F5FF", "#19DAEEFF", "#35ADC5D5"] : ["#F0FFFFFF", "#65FFFFFF", "#407EA2BA"])
                : Solid(Dark ? "#52616F" : "#A8BBC8");
            resources["SpecularBrush"] = GlassEffectsEnabled
                ? Gradient(Dark ? ["#65FFFFFF", "#08FFFFFF", "#00FFFFFF"] : ["#BCFFFFFF", "#20FFFFFF", "#00FFFFFF"])
                : Brushes.Transparent;
            _fallback = Gradient(Dark ? ["#263C42", "#22272D", "#303044"] : ["#E2F7FB", "#F9FBFC", "#F1F0FC"]);
            // Low-alpha tint leaves the native material visible; opaque paint hides it.
            _nativeTint = Gradient(Dark ? ["#292F555C", "#15232A32", "#253B3556"] : ["#37D8F3FA", "#18F8FBFF", "#32EDE9FD"]);
        }
        resources["WindowGradient"] = _fallback;
        resources["NativeWindowTint"] = _nativeTint;
        foreach (Window window in Application.Current.Windows) ApplyNative(window);
        Changed?.Invoke();
    }
    private static int ReadPersonalization(string value, int fallback)
    {
        try { return Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", value, fallback) is int found ? found : fallback; }
        catch (Exception error) when (error is UnauthorizedAccessException or System.Security.SecurityException or IOException) { return fallback; }
    }
    private static SolidColorBrush Solid(string hex)
    { var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex)); brush.Freeze(); return brush; }
    private static LinearGradientBrush Gradient(string[] colours)
    {
        var brush = new LinearGradientBrush { StartPoint = new Point(0, 0), EndPoint = new Point(.8, 1) };
        for (int index = 0; index < colours.Length; index++) brush.GradientStops.Add(new GradientStop((Color)ColorConverter.ConvertFromString(colours[index]), (double)index / (colours.Length - 1)));
        brush.Freeze(); return brush;
    }

    public static void ApplyNative(Window window, bool force = false)
    {
        var state = Windows.GetValue(window, _ => new NativeWindowState());
        if (!state.Attached)
        {
            state.Attached = true;
            window.SourceInitialized += (_, _) => ApplyNative(window);
            window.Closed += (_, _) => { if (state.Source is { IsDisposed: false } && state.Hook != null) state.Source.RemoveHook(state.Hook); };
        }
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero) return;
        var source = HwndSource.FromHwnd(handle);
        if (source?.CompositionTarget == null) return;
        if (state.Source == null)
        {
            state.Source = source;
            state.OriginalCompositionColour = source.CompositionTarget.BackgroundColor;
            state.Hook = (IntPtr hwnd, int message, IntPtr wparam, IntPtr lparam, ref bool handled) =>
            {
                if (message is SettingChanged or ThemeChanged) QueueApply();
                if (message == CompositionChanged) window.Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(() => ApplyNative(window, true)));
                return IntPtr.Zero;
            };
            source.AddHook(state.Hook);
        }
        if (!force && state.PaletteVersion == _paletteVersion) return;
        state.PaletteVersion = _paletteVersion;
        state.BackdropResult = null;
        state.FrameResult = null;
        bool useNative = false;
        state.Status = _policy.Reason;
        int dark = Dark ? 1 : 0, rounded = 2;
        try
        {
            _ = DwmSetWindowAttribute(handle, DarkModeAttribute, ref dark, sizeof(int));
            if (OperatingSystem.IsWindowsVersionAtLeast(10, 0, 22000))
                _ = DwmSetWindowAttribute(handle, CornerAttribute, ref rounded, sizeof(int));
            if (_policy.BackdropType != 1 && !window.AllowsTransparency && DwmIsCompositionEnabled(out bool composed) >= 0 && composed)
            {
                int backdrop = _policy.BackdropType;
                state.BackdropResult = DwmSetWindowAttribute(handle, BackdropAttribute, ref backdrop, sizeof(int));
                var glass = new Margins { Left = -1, Right = -1, Top = -1, Bottom = -1 };
                state.FrameResult = state.BackdropResult >= 0 ? DwmExtendFrameIntoClientArea(handle, ref glass) : state.BackdropResult;
                useNative = state.BackdropResult >= 0 && state.FrameResult >= 0;
                state.Status = useNative ? backdrop == 3 ? "Frosted Acrylic requested; Windows controls fallback" : "Balanced Mica requested; Windows controls fallback" : "Solid fallback: Windows could not apply the backdrop";
            }
            if (!useNative)
            {
                if (_policy.BackdropType != 1 && state.BackdropResult == null)
                    state.Status = "Solid fallback: native composition is unavailable for this window";
                int none = 1;
                if (OperatingSystem.IsWindowsVersionAtLeast(10, 0, 22621)) _ = DwmSetWindowAttribute(handle, BackdropAttribute, ref none, sizeof(int));
                var reset = new Margins();
                _ = DwmExtendFrameIntoClientArea(handle, ref reset);
            }
        }
        catch (Exception error) when (error is DllNotFoundException or EntryPointNotFoundException)
        { state.Status = "Solid fallback: native composition is unavailable"; }
        state.NativeActive = useNative;
        source.CompositionTarget.BackgroundColor = useNative ? Colors.Transparent : state.OriginalCompositionColour;
        window.SetCurrentValue(Window.BackgroundProperty, useNative ? _nativeTint : _fallback);
        // AllowsTransparency remains false: the application keeps native window controls.
    }
    public static NativeBackdropDiagnostics GetBackdropDiagnostics(Window window)
    {
        var state = Windows.GetValue(window, _ => new NativeWindowState());
        return new NativeBackdropDiagnostics(state.NativeActive, state.Status, GlassMaterial, GlassEffectsEnabled,
            state.BackdropResult, state.FrameResult, Environment.OSVersion.Version.Build, RenderCapability.Tier >> 16,
            SystemParameters.HighContrast, ReduceTransparency, ReadPersonalization("EnableTransparency", 1) != 0);
    }
    public sealed record NativeBackdropDiagnostics(bool NativeActive, string ActualMaterial, string RequestedMaterial,
        bool CardEffectsEnabled, int? BackdropHResult, int? FrameHResult, int WindowsBuild, int RenderingTier,
        bool HighContrast, bool ReducedTransparency, bool WindowsTransparencyEnabled);
    private sealed class NativeWindowState
    {
        public bool Attached, NativeActive;
        public int PaletteVersion = -1;
        public string Status = "Waiting for the native window";
        public int? BackdropResult, FrameResult;
        public Color OriginalCompositionColour;
        public HwndSource? Source;
        public HwndSourceHook? Hook;
    }
    [StructLayout(LayoutKind.Sequential)] private struct Margins { public int Left, Right, Top, Bottom; }
    [DllImport("dwmapi.dll", PreserveSig = true)] private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
    [DllImport("dwmapi.dll", PreserveSig = true)] private static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref Margins margins);
    [DllImport("dwmapi.dll", PreserveSig = true)] private static extern int DwmIsCompositionEnabled([MarshalAs(UnmanagedType.Bool)] out bool enabled);
}

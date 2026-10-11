using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace KarimEldamatyWindows;

/// <summary>Per-user Windows DPAPI storage. Keys and connection URLs never enter board files.</summary>
public static class CredentialStore
{
    private static string DirectoryPath => Path.Combine(ServicePaths.UserDataDirectory, "Credentials");
    private static string PathFor(string name)
    {
        if (string.IsNullOrEmpty(name) || name.Length > 80 || name.Any(c => !(char.IsAsciiLetterOrDigit(c) || c is '-' or '_'))) throw new ArgumentException("Invalid credential name.");
        return Path.Combine(DirectoryPath, name + ".dpapi");
    }
    public static void Save(string name, string value)
    {
        var path = PathFor(name);
        ArgumentNullException.ThrowIfNull(value);
        if (value.Length == 0 || Encoding.UTF8.GetByteCount(value) > 65536) throw new ArgumentException("Credentials must contain between 1 and 65,536 UTF-8 bytes.");
        var bytes = Encoding.UTF8.GetBytes(value);
        try
        {
            var encrypted = Protect(bytes, true);
            Directory.CreateDirectory(DirectoryPath);
            var pending = path + ".new";
            File.WriteAllBytes(pending, encrypted); File.Move(pending, path, true);
        }
        finally { System.Security.Cryptography.CryptographicOperations.ZeroMemory(bytes); }
    }
    public static string? Read(string name)
    {
        var path = PathFor(name); if (!File.Exists(path)) return null;
        var file = new FileInfo(path); if (file.Length > 131072) throw new InvalidDataException("The saved credential is invalid.");
        var bytes = Protect(File.ReadAllBytes(path), false);
        try { return Encoding.UTF8.GetString(bytes); }
        finally { System.Security.Cryptography.CryptographicOperations.ZeroMemory(bytes); }
    }
    public static void Delete(string name) { var path = PathFor(name); if (File.Exists(path)) File.Delete(path); }
    [StructLayout(LayoutKind.Sequential)] private struct Blob { public int Length; public IntPtr Data; }
    [DllImport("crypt32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern bool CryptProtectData(ref Blob input, string? description, IntPtr entropy, IntPtr reserved, IntPtr prompt, uint flags, out Blob output);
    [DllImport("crypt32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern bool CryptUnprotectData(ref Blob input, IntPtr description, IntPtr entropy, IntPtr reserved, IntPtr prompt, uint flags, out Blob output);
    [DllImport("kernel32.dll")] private static extern IntPtr LocalFree(IntPtr pointer);
    private static byte[] Protect(byte[] bytes, bool encrypt)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Windows DPAPI is required for credentials.");
        var input = new Blob { Length = bytes.Length, Data = Marshal.AllocHGlobal(bytes.Length) }; Blob output = default;
        try
        {
            Marshal.Copy(bytes, 0, input.Data, bytes.Length);
            var ok = encrypt ? CryptProtectData(ref input, "Karim Eldamaty private connection", IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 1, out output) : CryptUnprotectData(ref input, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 1, out output);
            if (!ok) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Windows could not access this user's encrypted credentials.");
            var result = new byte[output.Length]; Marshal.Copy(output.Data, result, 0, result.Length); return result;
        }
        finally
        {
            for (var i = 0; i < input.Length; i++) Marshal.WriteByte(input.Data, i, 0);
            Marshal.FreeHGlobal(input.Data);
            if (output.Data != IntPtr.Zero) { for (var i = 0; i < output.Length; i++) Marshal.WriteByte(output.Data, i, 0); LocalFree(output.Data); }
        }
    }
}

public enum AIBackend { Auto, Local, OpenAI }
public sealed class AISettingsConfig
{
    public AIBackend Backend { get; set; } = AIBackend.Auto;
    public string Model { get; set; } = "gpt-4.1";
    public string LocalModel { get; set; } = "";
    private static string SettingsPath => Path.Combine(ServicePaths.UserDataDirectory, "assistant.json");
    public static AISettingsConfig Load()
    {
        try { var value = File.Exists(SettingsPath) ? JsonSerializer.Deserialize<AISettingsConfig>(File.ReadAllText(SettingsPath)) ?? new() : new(); value.Validate(); return value; }
        catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException or ArgumentException) { return new(); }
    }
    public void Validate()
    {
        Model = (Model ?? "").Trim(); LocalModel = (LocalModel ?? "").Trim();
        if (!Enum.IsDefined(Backend)) throw new ArgumentException("Choose Auto, Local or OpenAI.");
        if (Model.Length is < 1 or > 120 || LocalModel.Length > 120 || Model.Any(char.IsControl) || LocalModel.Any(char.IsControl)) throw new ArgumentException("Use a valid model name of at most 120 characters.");
    }
    public void Save()
    {
        Validate();
        Directory.CreateDirectory(Path.GetDirectoryName(SettingsPath)!);
        File.WriteAllText(SettingsPath + ".new", JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(SettingsPath + ".new", SettingsPath, true);
    }
    public AIBackend EffectiveBackend => Backend == AIBackend.Auto ? (LocalModel.Length > 0 ? AIBackend.Local : AIBackend.OpenAI) : Backend;
    public string RouteDescription => EffectiveBackend == AIBackend.Local ? "Local Ollama · 127.0.0.1 · " + (LocalModel.Length > 0 ? LocalModel : "choose a model") : "OpenAI cloud · " + Model;
}

internal static class ServicePaths
{
    public static string UserDataDirectory => App.TestDataDirectory ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "KarimEldamaty");
}

internal static class ServiceHttp
{
    private static readonly Lazy<System.Net.Http.HttpClient> network = new(() => CreateClient(false));
    private static readonly Lazy<System.Net.Http.HttpClient> loopback = new(() => CreateClient(true));
    public static System.Net.Http.HttpClient NetworkClient => network.Value;
    public static System.Net.Http.HttpClient LoopbackClient => loopback.Value;
    private static System.Net.Http.HttpClient CreateClient(bool local) => new(new System.Net.Http.SocketsHttpHandler { AllowAutoRedirect = false, UseProxy = !local, MaxConnectionsPerServer = 2, PooledConnectionIdleTimeout = TimeSpan.FromMinutes(1), PooledConnectionLifetime = TimeSpan.FromMinutes(5) }) { Timeout = Timeout.InfiniteTimeSpan };

    public static async Task<string> ReadBoundedAsync(System.Net.Http.HttpResponseMessage response, int maximumBytes, CancellationToken ct)
    {
        if (response.Content.Headers.ContentLength > maximumBytes) throw new InvalidDataException("The service response was too large.");
        await using var stream = await response.Content.ReadAsStreamAsync(ct); using var memory = new MemoryStream(); var buffer = new byte[8192];
        int read; while ((read = await stream.ReadAsync(buffer, ct)) > 0) { if (memory.Length + read > maximumBytes) throw new InvalidDataException("The service response was too large."); await memory.WriteAsync(buffer.AsMemory(0, read), ct); }
        return Encoding.UTF8.GetString(memory.ToArray());
    }
}

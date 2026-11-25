using System.Net.Http;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace KarimEldamatyWindows;

internal sealed record WindowsRelease(Version Version, int? TestNumber, string Tag)
{
    public string Page => $"{ReleaseSupport.Releases}/tag/{Tag}";
    public string Label => TestNumber is int preview ? $"{Version} Test {preview}" : Version.ToString();
    public string PackageName => $"Velin-{Tag[WindowsUpdates.TagPrefix.Length..]}-Windows-x64.zip";

    public bool IsNewerThan(WindowsRelease other)
    {
        var order = Version.CompareTo(other.Version);
        return order != 0 ? order > 0 : (TestNumber ?? int.MaxValue) > (other.TestNumber ?? int.MaxValue);
    }
}

internal static partial class WindowsUpdates
{
    public const string TagPrefix = "velin-windows-v";
    private const int PageSize = 30;
    private static readonly HttpClient Client = new(new HttpClientHandler { AllowAutoRedirect = false })
    {
        Timeout = TimeSpan.FromSeconds(12),
        MaxResponseContentBufferSize = 8 * 1024 * 1024,
        DefaultRequestHeaders =
        {
            { "User-Agent", "Velin-Windows/1" },
            { "Accept", "application/vnd.github+json" },
            { "X-GitHub-Api-Version", "2022-11-28" }
        }
    };

    [GeneratedRegex(@"^velin-windows-v(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})(?:-test\.([1-9][0-9]{0,8}))?$", RegexOptions.CultureInvariant)]
    private static partial Regex TagPattern();

    public static WindowsRelease? ParseTag(string tag)
    {
        var match = TagPattern().Match(tag);
        if (!match.Success) return null;
        var version = new Version(int.Parse(match.Groups[1].Value), int.Parse(match.Groups[2].Value),
            int.Parse(match.Groups[3].Value));
        int? test = match.Groups[4].Success ? int.Parse(match.Groups[4].Value) : null;
        return new(version, test, tag);
    }

    public static async Task<WindowsRelease?> CheckAsync(CancellationToken cancellation)
    {
        var current = ParseTag(TagPrefix + ReleaseSupport.Version) ?? throw new InvalidDataException("Invalid installed version.");
        WindowsRelease? newest = null;
        for (var page = 1; ; page++)
        {
            var endpoint = $"https://api.github.com/repos/{ReleaseSupport.Repository}/releases?per_page={PageSize}&page={page}";
            var json = await Client.GetStringAsync(endpoint, cancellation).ConfigureAwait(false);
            using var doc = JsonDocument.Parse(json);
            newest = PickNewest(doc.RootElement, current, newest);
            if (doc.RootElement.GetArrayLength() < PageSize) return newest;
        }
    }

    internal static WindowsRelease? PickNewest(JsonElement releases, WindowsRelease current, WindowsRelease? newest = null)
    {
        foreach (var release in releases.EnumerateArray())
        {
            if (release.GetProperty("draft").GetBoolean()) continue;
            var candidate = ParseTag(release.GetProperty("tag_name").GetString() ?? "");
            if (candidate is null || !candidate.IsNewerThan(current) ||
                (newest is not null && !candidate.IsNewerThan(newest))) continue;
            if (release.GetProperty("prerelease").GetBoolean() != candidate.TestNumber.HasValue) continue;
            var assets = release.GetProperty("assets").EnumerateArray().Where(asset =>
                asset.GetProperty("state").GetString() == "uploaded" && asset.GetProperty("size").GetInt64() > 0)
                .Select(asset => asset.GetProperty("name").GetString()).ToHashSet(StringComparer.Ordinal);
            if (assets.Contains(candidate.PackageName) && assets.Contains("SHA256SUMS.txt")) newest = candidate;
        }
        return newest;
    }
}

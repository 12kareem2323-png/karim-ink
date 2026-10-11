namespace KarimEldamatyWindows;

/// Shared catalogue contract for the virtualised library and canvas placement.
public sealed class SymbolEntry
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Category { get; set; } = "";
    public List<string> Keywords { get; set; } = [];
}

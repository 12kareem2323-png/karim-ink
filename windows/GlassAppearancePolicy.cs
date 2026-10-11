namespace KarimEldamatyWindows;

/// <summary>Pure decisions: no native calls, registry reads or UI state.</summary>
public readonly record struct GlassPolicy(bool EffectsEnabled, int BackdropType, string Reason)
{
    public static GlassPolicy Evaluate(string material, bool reducedTransparency, bool highContrast,
        bool windowsTransparency, bool remoteSession, int windowsBuild, int renderingTier)
    {
        if (highContrast) return Solid("Solid: Windows high contrast");
        if (reducedTransparency || material == "Solid") return Solid("Solid: reduced transparency");
        if (!windowsTransparency) return Solid("Solid: Windows transparency is disabled");
        if (remoteSession) return Solid("Solid: remote desktop session");
        if (renderingTier == 0) return Solid("Solid: software rendering");
        if (windowsBuild < 22621) return new GlassPolicy(true, 1, "Tinted glass: native backdrop requires Windows 11 22H2 or later");
        return new GlassPolicy(true, material == "Frosted" ? 3 : 2, material == "Frosted" ? "Frosted Acrylic" : "Balanced Mica");
    }
    private static GlassPolicy Solid(string reason) => new(false, 1, reason);
}

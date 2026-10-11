using System.Runtime.CompilerServices;
namespace KarimEldamatyWindows;

/// Internal history snapshots share only their private, immutable element copies.
/// Restoring history always clones before the result reaches editable application state.
internal sealed class BoardHistorySnapshots
{
    private sealed record FrozenElement(long Signature,DrawingElement Element);
    private readonly ConditionalWeakTable<DrawingElement,FrozenElement> elements=new();
    public long CopiedElements {get;private set;}
    public Board Capture(Board source)
    {
        var snapshot=BoardCodec.CloneHeader(source);
        foreach(var item in source.Elements){var signature=item.RenderSignature;if(!elements.TryGetValue(item,out var frozen)||frozen.Signature!=signature){elements.Remove(item);frozen=new(signature,BoardCodec.Clone(item));elements.Add(item,frozen);CopiedElements++;}snapshot.Elements.Add(frozen.Element);}return snapshot;
    }
}

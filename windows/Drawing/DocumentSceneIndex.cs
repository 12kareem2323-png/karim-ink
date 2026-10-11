using System.Windows;
namespace KarimEldamatyWindows;

/// Drawing-space index. Synchronizing an unchanged element reads a constant-size render key;
/// interior point edits invalidate its key through the sample owner notification.
public sealed class DocumentSceneIndex
{
    private const int CellSize=512;
    private sealed record Entry(DrawingElement Element,Rect Bounds,long Signature,int Order,long Serial);
    private readonly Dictionary<Guid,Entry> entries=[];
    private readonly Dictionary<(int,int),HashSet<Guid>> cells=[];
    private readonly HashSet<Guid> large=[];
    private long serial;
    public int Count=>entries.Count;
    public long GeometryRebuildCount {get;private set;}
    public void Clear(){entries.Clear();cells.Clear();large.Clear();}
    public bool Contains(Guid id)=>entries.ContainsKey(id);
    public long Signature(Guid id)=>entries[id].Signature;
    public int Order(Guid id)=>entries[id].Order;
    public void Synchronize(Board board)
    {
        var present=new HashSet<Guid>();for(int i=0;i<board.Elements.Count;i++){var e=board.Elements[i];present.Add(e.Id);var signature=e.RenderSignature;if(entries.TryGetValue(e.Id,out var old)&&old.Signature==signature&&ReferenceEquals(old.Element,e)){if(old.Order!=i)entries[e.Id]=old with{Order=i};continue;}Upsert(e,i);}
        foreach(var id in entries.Keys.Where(id=>!present.Contains(id)).ToArray())Remove(id);
    }
    public void Upsert(DrawingElement e,int order)
    {
        Remove(e.Id);var bounds=e.Bounds;entries[e.Id]=new(e,bounds,e.RenderSignature,order,++serial);GeometryRebuildCount++;
        if(bounds.IsEmpty)return;var (left,right,top,bottom)=Range(bounds);if((long)(right-left+1)*(bottom-top+1)>256){large.Add(e.Id);return;}
        for(var x=left;x<=right;x++)for(var y=top;y<=bottom;y++){if(!cells.TryGetValue((x,y),out var bucket))cells[(x,y)]=bucket=[];bucket.Add(e.Id);}
    }
    public void Remove(Guid id)
    {
        if(!entries.Remove(id,out var entry))return;if(large.Remove(id)||entry.Bounds.IsEmpty)return;var (left,right,top,bottom)=Range(entry.Bounds);for(var x=left;x<=right;x++)for(var y=top;y<=bottom;y++)if(cells.TryGetValue((x,y),out var bucket)){bucket.Remove(id);if(bucket.Count==0)cells.Remove((x,y));}
    }
    public IReadOnlyList<DrawingElement> Query(Rect bounds)
    {
        if(bounds.IsEmpty)return[];var candidates=new HashSet<Guid>(large);var (left,right,top,bottom)=Range(bounds);
        // Very wide views enumerate indexed objects once instead of millions of empty cells.
        if((long)(right-left+1)*(bottom-top+1)>Math.Max(4096,cells.Count*2L))candidates.UnionWith(entries.Keys);else for(var x=left;x<=right;x++)for(var y=top;y<=bottom;y++)if(cells.TryGetValue((x,y),out var bucket))candidates.UnionWith(bucket);
        return candidates.Select(id=>entries[id]).Where(entry=>entry.Bounds.IntersectsWith(bounds)).OrderBy(entry=>entry.Order).ThenBy(entry=>entry.Serial).Select(entry=>entry.Element).ToArray();
    }
    private static (int Left,int Right,int Top,int Bottom) Range(Rect r)=>((int)Math.Floor(r.Left/CellSize),(int)Math.Floor(r.Right/CellSize),(int)Math.Floor(r.Top/CellSize),(int)Math.Floor(r.Bottom/CellSize));
}

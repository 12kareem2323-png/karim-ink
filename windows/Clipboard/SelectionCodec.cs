using System.Text;
using System.Text.Json;
namespace KarimEldamatyWindows;

/// Portable, versioned clipboard data. Native image and text formats are added by the UI layer.
public static class SelectionCodec
{
    public const string Format = "KarimEldamaty.Selection.v1";
    public const int MaximumPayloadBytes = 32 * 1024 * 1024;
    public static string Encode(Board source, IReadOnlySet<Guid> selected)
    {
        // Copy only the selection: unrelated large strokes and embedded images stay untouched.
        var board = new Board { Version=source.Version, Background=source.Background,
            Width=source.Width, Height=source.Height, GridSpacing=source.GridSpacing,
            PointsPerMM=source.PointsPerMM, ScaleDenominator=source.ScaleDenominator,
            Elements=source.Elements.Where(e=>selected.Contains(e.Id)).Select(BoardCodec.Clone).ToList() };
        if(board.Elements.Count == 0) throw new InvalidDataException("Select drawing objects before copying.");
        // Retain only the metadata required by the selected fragments; exclude private notes/URLs.
        board.Id = Guid.NewGuid();board.Title="Copied drawing objects";board.Notes="";board.NotionURL="";board.WhiteboardURL="";board.Folder="General";
        var needed = board.Elements.Select(e => e.Extra?.GetValueOrDefault("windowsEraseSourceKey")).Where(x=>x?.ValueKind==JsonValueKind.String).Select(x=>x!.Value.GetString()!).ToHashSet();
        board.Extra = source.Extra?.Where(pair=>needed.Contains(pair.Key)).ToDictionary(pair=>pair.Key,pair=>pair.Value);
        var json = BoardCodec.Serialize(board);
        if(Encoding.UTF8.GetByteCount(json)>MaximumPayloadBytes)throw new InvalidDataException("This selection is too large for the clipboard. Export its .engboard file instead.");
        return json;
    }
    public static Board Decode(string json)
    {
        if(Encoding.UTF8.GetByteCount(json)>MaximumPayloadBytes)throw new InvalidDataException("Clipboard drawing data exceeds 32 MB.");
        return BoardCodec.Deserialize(json);
    }
    public static int Paste(DrawingSession session, string json, double targetX, double targetY)
    {
        if(!double.IsFinite(targetX)||!double.IsFinite(targetY))throw new ArgumentException("Invalid paste position.");
        var copied=Decode(json);if(copied.Elements.Count==0)return 0;
        var left=copied.Elements.Min(e=>e.Bounds.Left);var top=copied.Elements.Min(e=>e.Bounds.Top);
        if(!double.IsFinite(left)||!double.IsFinite(top))throw new InvalidDataException("Clipboard objects have no visible geometry.");
        var dx=targetX-left;var dy=targetY-top;
        var ids=copied.Elements.ToDictionary(e=>e.Id,_=>Guid.NewGuid());var sourceMap=new Dictionary<string,string>();
        foreach(var e in copied.Elements)
        {
            var old=e.Id;e.Id=ids[old];e.Locked=false;e.Translate(dx,dy);
            if(e.Extra?.GetValueOrDefault("windowsEraseSourceKey") is {ValueKind:JsonValueKind.String} reference)
            {
                var key=reference.GetString()!;
                if(!sourceMap.TryGetValue(key,out var newKey))sourceMap[key]=newKey="windowsEraseSource-"+Guid.NewGuid().ToString("D");
                e.Extra["windowsEraseSourceKey"]=JsonSerializer.SerializeToElement(newKey);
            }
        }
        // Validate the entire proposed result before creating history or changing the destination.
        var candidate=BoardCodec.Clone(session.Board);candidate.Elements.AddRange(copied.Elements);
        candidate.Extra??=[];
        foreach(var pair in sourceMap)if(copied.Extra?.TryGetValue(pair.Key,out var samples)==true)candidate.Extra[pair.Value]=samples;
        BoardCodec.Validate(candidate);
        session.Checkpoint();session.Board.Elements.AddRange(copied.Elements);
        if(sourceMap.Count>0){session.Board.Extra??=[];foreach(var pair in sourceMap)if(candidate.Extra.TryGetValue(pair.Value,out var samples))session.Board.Extra[pair.Value]=samples;}
        session.SelectedIds=copied.Elements.Select(e=>e.Id).ToHashSet();session.Tool="Select";session.PendingSymbolId=null;session.NotifyChanged();return copied.Elements.Count;
    }
    public static string PlainText(Board board)=>string.Join(Environment.NewLine,board.Elements.Where(e=>e.Kind=="text"||e.Kind=="symbol"&&e.Text.StartsWith("mathlatex:",StringComparison.Ordinal)).Select(e=>e.Kind=="text"?e.Text:e.Text[10..]));
}

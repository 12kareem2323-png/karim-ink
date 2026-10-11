using System.Windows;
namespace KarimEldamatyWindows;
public class DrawingSession
{
    public Board Board { get; private set; } = new();
    public string Tool { get; set; } = "Draw";
    public string Pen { get; set; } = "Technical Fineliner";
    public BrushSettings Settings { get; set; } = BrushSettings.Defaults("Technical Fineliner");
    public InkColor Color { get; set; } = InkColor.Graphite;
    public double Zoom { get; set; } = 1;
    public Point Offset { get; set; } = new(30,30);
    public HashSet<Guid> SelectedIds { get; set; } = [];
    public string? PendingSymbolId { get; set; }
    public bool Snap { get; set; }
    public bool AutoCorrect { get; set; } = true;
    public int Revision { get; private set; }
    public string Dash { get; set; } = "Solid";
    public bool FillShapes { get; set; }
    public double Smoothing { get; set; } = .45;
    public double ActivationPressure { get; set; } = .01;
    public bool ShowRuler { get; set; }
    public bool ShowProtractor { get; set; }
    public bool ShowSymbolAnimations { get; set; } = true;
    public double FixedLineLengthMM { get; set; }
    public string EraserMode { get; set; } = "Stroke";
    public double EraserRadius { get; set; } = 20;
    public PenInputCapabilities InputCapabilities { get; internal set; } = new();
    public string BarrelButtonAction { get; set; } = "Pan";
    public double? LiveRawPressure { get; internal set; }
    public bool PenActive { get; internal set; }
    public double? LivePressure { get; internal set; }
    public Point LiveTilt { get; internal set; }
    public string? InputDeviceKey { get; internal set; }
    public event Action? Changed;
    public event Action? InputChanged;
    internal void NotifyInputChanged() => InputChanged?.Invoke();
    public event Action<string>? StatusChanged;
    private sealed record HistorySnapshot(Board Board,long Sequence);
    private readonly List<HistorySnapshot> undo = [];
    private readonly List<HistorySnapshot> redo = [];
    private long historySequence;
    private readonly BoardHistorySnapshots historySnapshots=new();
    public const long HistoryBudgetBytes = 64L * 1024 * 1024;
    public long EstimatedHistoryBytes { get; private set; }
    public bool HistoryBudgetExceeded => EstimatedHistoryBytes > HistoryBudgetBytes;
    // Estimates managed object/sample/string storage and distinct image/JSON payloads.
    // One newest snapshot is always retained, even when a single large board exceeds the budget.
    private long EstimateHistory()
    {
        long bytes=0;var images=new HashSet<byte[]>(ReferenceEqualityComparer.Instance);var json=new HashSet<System.Text.Json.JsonElement>();var countedElements=new HashSet<DrawingElement>(ReferenceEqualityComparer.Instance);
        void Extra(Dictionary<string,System.Text.Json.JsonElement>? fields) {
            if(fields is null)return;bytes+=72+fields.Count*64L;
            foreach(var pair in fields){bytes+=pair.Key.Length*2L;if(json.Add(pair.Value)&&pair.Value.ValueKind!=System.Text.Json.JsonValueKind.Undefined)bytes+=pair.Value.GetRawText().Length*2L+64;}
        }
        foreach(var item in undo.Concat(redo)) {
            var board=item.Board;bytes+=512+(board.Title.Length+board.Notes.Length+board.Folder.Length+board.NotionURL.Length+board.WhiteboardURL.Length)*2L;Extra(board.Extra);
            foreach(var e in board.Elements){bytes+=8;if(!countedElements.Add(e))continue;bytes+=384+e.Text.Length*2L+e.Points.Count*200L;Extra(e.Extra);Extra(e.Color.Extra);Extra(e.BrushSettings?.Extra);foreach(var point in e.Points)Extra(point.Extra);if(e.ImageData is {} data&&images.Add(data))bytes+=data.LongLength;if(e.Sketch3D is {} scene&&json.Add(scene))bytes+=scene.GetRawText().Length*2L+64;}
        }
        return bytes;
    }
    private void TrimHistory()
    {
        var removed=false;EstimatedHistoryBytes=EstimateHistory();
        while(undo.Count+redo.Count>1&&(undo.Count+redo.Count>40||EstimatedHistoryBytes>HistoryBudgetBytes)) {
            var firstUndo=undo.Count==0?long.MaxValue:undo[0].Sequence;var firstRedo=redo.Count==0?long.MaxValue:redo[0].Sequence;
            if(firstUndo<firstRedo)undo.RemoveAt(0);else redo.RemoveAt(0);removed=true;EstimatedHistoryBytes=EstimateHistory();
        }
        if(removed)Status("Older undo steps were released to limit history memory. The newest step is retained.");
    }
    public int UndoStepCount => undo.Count;
    public int RedoStepCount => redo.Count;
    public bool CanUndo => undo.Count > 0;
    public bool CanRedo => redo.Count > 0;
    public void SetBoard(Board board) { BoardCodec.Validate(board); Board = BoardCodec.Clone(board); undo.Clear(); redo.Clear(); EstimatedHistoryBytes=0; SelectedIds.Clear(); PendingSymbolId=null; Revision++; Changed?.Invoke(); }
    public void Checkpoint() { undo.Add(new(historySnapshots.Capture(Board),++historySequence)); redo.Clear(); TrimHistory(); }
    public void NotifyChanged() { BoardCodec.PruneDerivedMetadata(Board); Board.Modified = SwiftDate.Now; Revision++; SelectedIds.IntersectWith(Board.Elements.Select(e=>e.Id)); Changed?.Invoke(); }
    public void NotifyViewChanged() => Changed?.Invoke();
    public void Status(string text) => StatusChanged?.Invoke(text);
    public void Commit(DrawingElement e) { Checkpoint(); Board.Elements.Add(e); NotifyChanged(); }
    public void Undo() { if (undo.Count == 0) return; var target=undo[^1].Board; undo.RemoveAt(undo.Count-1); redo.Add(new(historySnapshots.Capture(Board),++historySequence)); Board = BoardCodec.Clone(target); TrimHistory(); SelectedIds.Clear(); NotifyChanged(); }
    public void Redo() { if (redo.Count == 0) return; var target=redo[^1].Board; redo.RemoveAt(redo.Count-1); undo.Add(new(historySnapshots.Capture(Board),++historySequence)); Board = BoardCodec.Clone(target); TrimHistory(); SelectedIds.Clear(); NotifyChanged(); }
    public void DeleteSelection() { if (!Board.Elements.Any(e => SelectedIds.Contains(e.Id) && !e.Locked)) return; Checkpoint(); Board.Elements.RemoveAll(e => SelectedIds.Contains(e.Id) && !e.Locked); SelectedIds.Clear(); NotifyChanged(); }
    public void AddText(string text,double x,double y,double fontSize=24) { if (string.IsNullOrWhiteSpace(text)) return; Commit(new() { Kind="text", Text=text, FontSize=fontSize, Points=[new(x,y)], Color=Color, Width=Settings.MaxWidth }); }
    public void DuplicateSelection() { var items = Board.Elements.Where(e=>SelectedIds.Contains(e.Id)).Select(BoardCodec.Clone).ToList(); if(items.Count == 0)return; Checkpoint(); SelectedIds.Clear(); foreach(var e in items) {e.Id = Guid.NewGuid(); e.Translate(24,24); e.Locked = false; Board.Elements.Add(e); SelectedIds.Add(e.Id);} NotifyChanged(); }
    public void SelectAll() { SelectedIds = Board.Elements.Select(e=>e.Id).ToHashSet(); Tool = "Select"; NotifyViewChanged(); }
    public void SetPen(string name) { Pen = BrushSettings.PenNames.Contains(name) ? name : "Technical Fineliner"; Settings = BrushSettings.Defaults(Pen); NotifyViewChanged(); }
}

using System.Collections.ObjectModel;
using System.Security.Cryptography;
namespace KarimEldamatyWindows;
public sealed class BoardStore : IDisposable
{
    public string DirectoryPath { get; }
    public ObservableCollection<Board> Boards { get; } = [];
    public string? Error { get; private set; }
    public Guid? ConflictingBoardId { get; private set; }
    public event Action? Changed;
    private readonly SynchronizationContext? context = SynchronizationContext.Current;
    private readonly SemaphoreSlim gate = new(1,1);
    private readonly Dictionary<Guid,string> fingerprints = [];
    private readonly object pendingGate = new();
    private readonly Dictionary<Guid,(Board Snapshot,long Sequence)> pending = [];
    private readonly Dictionary<Guid,long> latestRequests = [];
    private long sequence;
    private CancellationTokenSource? debounce;
    private Task lastWorker = Task.CompletedTask;
    private bool disposed;
    public BoardStore(string? directoryPath = null) { DirectoryPath = directoryPath ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Karim Eldamaty","Boards"); }
    public string PathFor(Guid id) => Path.Combine(DirectoryPath, id.ToString("D").ToUpperInvariant() + ".engboard");
    private string ExistingPath(Guid id) => Directory.Exists(DirectoryPath) ? Directory.EnumerateFiles(DirectoryPath,"*.engboard").FirstOrDefault(p=>string.Equals(Path.GetFileNameWithoutExtension(p),id.ToString("D"),StringComparison.OrdinalIgnoreCase)) ?? PathFor(id) : PathFor(id);
    public async Task LoadAsync()
    {
        await gate.WaitAsync();
        try {
            var result = await Task.Run(() => {
                Directory.CreateDirectory(DirectoryPath); var list = new List<Board>(); var errors = new List<string>(); fingerprints.Clear();
                foreach(var path in Directory.EnumerateFiles(DirectoryPath,"*.engboard")) try { var b = BoardCodec.Read(path); if(list.Any(x=>x.Id == b.Id)) throw new InvalidDataException("Duplicate board identifier."); list.Add(b); fingerprints[b.Id] = Fingerprint(File.ReadAllBytes(path)); } catch(Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Text.Json.JsonException or ArgumentException) {errors.Add(Path.GetFileName(path)+": "+ex.Message);}
                return (list.OrderByDescending(b=>b.Modified).ToList(), errors.Count == 0 ? null : string.Join(Environment.NewLine,errors));
            });
            OnContext(() => { Boards.Clear(); foreach(var b in result.Item1) Boards.Add(b); Error = result.Item2; Changed?.Invoke(); });
        } finally { gate.Release(); }
    }
    public bool Save(Board board) { var snapshot = BoardCodec.Clone(board); return SaveAsync(snapshot).GetAwaiter().GetResult(); }
    public Task<bool> SaveAsync(Board board)
    {
        long request;lock(pendingGate){request=++sequence;latestRequests[board.Id]=request;pending.Remove(board.Id);}
        return SaveSnapshotAsync(board,request);
    }
    private async Task<bool> SaveSnapshotAsync(Board board,long request)
    {
        Board snapshot;
        try { snapshot = BoardCodec.Clone(board); } catch(Exception ex) { OnContext(()=> {Error = ex.Message; Changed?.Invoke();}); return false; }
        await gate.WaitAsync().ConfigureAwait(false);
        try {
            lock(pendingGate){if(latestRequests.TryGetValue(snapshot.Id,out var newest)&&request<newest)return true;}
            await Task.Run(() => Persist(snapshot)).ConfigureAwait(false);
            OnContext(()=> { var old = Boards.FirstOrDefault(b=>b.Id == snapshot.Id); if(old is not null) Boards.Remove(old); var index = 0; while(index < Boards.Count && Boards[index].Modified > snapshot.Modified)index++; Boards.Insert(index,snapshot); Error = null; ConflictingBoardId = null; Changed?.Invoke(); });
            return true;
        } catch(Exception ex) when(ex is IOException or UnauthorizedAccessException or System.Text.Json.JsonException or InvalidOperationException) { OnContext(()=> {Error = ex.Message; Changed?.Invoke();}); return false; }
        finally { gate.Release(); }
    }
    public void ScheduleSave(Board board)
    {
        if(disposed)return;
        Board snapshot;
        try { snapshot = BoardCodec.Clone(board); } catch(Exception ex) {OnContext(()=> {Error = ex.Message; Changed?.Invoke();});return;}
        lock(pendingGate) {
            var request=++sequence;latestRequests[board.Id]=request;pending[board.Id] = (snapshot,request); debounce?.Cancel(); debounce?.Dispose(); debounce = new(); var token = debounce.Token;
            lastWorker = Task.Run(async () => {try {await Task.Delay(650,token); await DrainAsync();} catch(OperationCanceledException) {}});
        }
    }
    private async Task DrainAsync()
    {
        while(true) { List<(Board Snapshot,long Sequence)> snapshots; lock(pendingGate) { if(pending.Count == 0)return; snapshots = pending.Values.ToList(); pending.Clear(); } foreach(var item in snapshots)await SaveSnapshotAsync(item.Snapshot,item.Sequence).ConfigureAwait(false); }
    }
    public async Task FlushAsync() { Task worker; lock(pendingGate) {debounce?.Cancel();worker = lastWorker;} await worker.ConfigureAwait(false); await DrainAsync().ConfigureAwait(false); }
    public async Task<bool> DeleteAsync(Board board)
    {
        await FlushAsync(); await gate.WaitAsync();
        try { var path = ExistingPath(board.Id); var archive = Path.Combine(DirectoryPath,"Archive","Deleted"); Directory.CreateDirectory(archive); if(File.Exists(path)) File.Move(path,Path.Combine(archive,board.Id+"-"+DateTime.UtcNow.ToString("yyyyMMddHHmmssfff")+".engboard")); fingerprints.Remove(board.Id); OnContext(()=> {var old = Boards.FirstOrDefault(x=>x.Id == board.Id); if(old is not null)Boards.Remove(old); Changed?.Invoke();}); return true; }
        catch(Exception ex) when(ex is IOException or UnauthorizedAccessException) {Error=ex.Message;return false;} finally {gate.Release();}
    }
    private void Persist(Board board)
    {
        var data = BoardCodec.SerializeBytes(board); Directory.CreateDirectory(DirectoryPath); var lockDir = Path.Combine(DirectoryPath,".locks"); Directory.CreateDirectory(lockDir);
        FileStream lockFile;
        try {lockFile = new(Path.Combine(lockDir,board.Id+".lock"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);} catch(IOException ex) {throw new IOException("Another app instance is saving this drawing. Try again shortly.",ex);}
        using(lockFile) {
            var target = ExistingPath(board.Id); byte[]? existing = File.Exists(target) ? File.ReadAllBytes(target) : null; var actual = existing is null ? null : Fingerprint(existing); fingerprints.TryGetValue(board.Id,out var expected);
            if(actual != expected) {
                var semanticEqual = false;
                try {semanticEqual = existing is not null && BoardCodec.Serialize(BoardCodec.Deserialize(existing)) == BoardCodec.Serialize(board);} catch(Exception ex) when(ex is IOException or System.Text.Json.JsonException) { }
                if(!semanticEqual) {
                    var conflicts = Path.Combine(DirectoryPath,"Archive","Conflicts",board.Id.ToString("D")); Directory.CreateDirectory(conflicts); Preserve(conflicts,"incoming",data); if(existing is not null)Preserve(conflicts,"saved",existing); OnContext(()=>ConflictingBoardId=board.Id);
                    throw new IOException("Another instance changed or removed this drawing. Both versions were preserved in Archive/Conflicts. Save your edits as a new drawing or reload the saved version.");
                }
            }
            var temporary = target+"."+Guid.NewGuid().ToString("N")+".tmp";
            try {using(var stream = new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None,65536,FileOptions.WriteThrough)) {stream.Write(data);stream.Flush(true);} if(File.Exists(target)) File.Replace(temporary,target,null); else File.Move(temporary,target); fingerprints[board.Id] = Fingerprint(data); }
            finally { if(File.Exists(temporary))File.Delete(temporary); }
        }
    }
    private static void Preserve(string folder,string role,byte[] data) {var path = Path.Combine(folder,role+"-"+Fingerprint(data)+".engboard");if(!File.Exists(path))using(var f = new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.Read)) {f.Write(data);f.Flush(true);}}
    private static string Fingerprint(byte[] data) => Convert.ToHexString(SHA256.HashData(data));
    private void OnContext(Action action) {if(context is null || SynchronizationContext.Current == context)action();else context.Post(_=>action(),null);}
    public void Dispose() {disposed = true; lock(pendingGate){debounce?.Cancel();debounce?.Dispose();} gate.Dispose();}
}

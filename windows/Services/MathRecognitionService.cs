using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
namespace KarimEldamatyWindows;

public sealed class MathSymbolDefinition
{
    public string Id { get; set; } = "";
    public string Command { get; set; } = "";
    public string? Package { get; set; }
    public string Display => MathSymbolCatalog.ToUnicode(Command) ?? Command;
    public override string ToString() => Display + "   " + Command;
}
public sealed record MathSymbolCandidate(string Label, string Command, double Probability)
{
    public string Latex => Command;
    public string Display => MathSymbolCatalog.ToUnicode(Command) ?? Command;
    public double Confidence => Probability;
    public override string ToString() => $"{Display}   {Command}   {Probability:P1}";
}
public static class MathSymbolCatalog
{
    private static readonly Lazy<IReadOnlyList<MathSymbolDefinition>> definitions = new(() =>
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Resources", "MathSymbols", "symbols.json");
        if (!File.Exists(path)) throw new FileNotFoundException("The local maths symbol catalogue is missing. Reinstall the app.");
        var all = JsonSerializer.Deserialize<List<MathSymbolDefinition>>(File.ReadAllText(path), new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? [];
        if (all.Count != 1098 || all.Any(x => string.IsNullOrEmpty(x.Id) || string.IsNullOrEmpty(x.Command)) || all.Select(x=>x.Id).Distinct().Count() != all.Count) throw new InvalidDataException("The local maths symbol catalogue is invalid.");
        return all.AsReadOnly();
    });
    private static readonly Lazy<IReadOnlyDictionary<string,MathSymbolDefinition>> byId = new(() => All.ToDictionary(x=>x.Id));
    public static IReadOnlyList<MathSymbolDefinition> All => definitions.Value;
    internal static IReadOnlyDictionary<string,MathSymbolDefinition> ById => byId.Value;
    public static IReadOnlyList<MathSymbolDefinition> Search(string query) => All.Where(x => x.Command.Contains(query, StringComparison.OrdinalIgnoreCase) || x.Id.Contains(query, StringComparison.OrdinalIgnoreCase) || x.Display.Contains(query, StringComparison.OrdinalIgnoreCase)).ToArray();
    private static readonly Dictionary<string,string> glyphs = new()
    {
        ["\\alpha"]="α",["\\beta"]="β",["\\gamma"]="γ",["\\delta"]="δ",["\\epsilon"]="ε",["\\varepsilon"]="ε",["\\theta"]="θ",["\\lambda"]="λ",["\\mu"]="μ",["\\nu"]="ν",["\\pi"]="π",["\\rho"]="ρ",["\\sigma"]="σ",["\\tau"]="τ",["\\phi"]="φ",["\\varphi"]="φ",["\\omega"]="ω",["\\Delta"]="Δ",["\\Omega"]="Ω",["\\Sigma"]="Σ",["\\Phi"]="Φ",
        ["\\pm"]="±",["\\times"]="×",["\\cdot"]="·",["\\div"]="÷",["\\neq"]="≠",["\\ne"]="≠",["\\leq"]="≤",["\\le"]="≤",["\\geq"]="≥",["\\ge"]="≥",["\\approx"]="≈",["\\infty"]="∞",["\\partial"]="∂",["\\nabla"]="∇",["\\int"]="∫",["\\sum"]="∑",["\\prod"]="∏",["\\sqrt"]="√",["\\surd"]="√",["\\rightarrow"]="→",["\\leftarrow"]="←",["\\leftrightarrow"]="↔",["\\Rightarrow"]="⇒",["\\Leftarrow"]="⇐",["\\Leftrightarrow"]="⇔",["\\uparrow"]="↑",["\\downarrow"]="↓",["\\mapsto"]="↦",
        ["\\forall"]="∀",["\\exists"]="∃",["\\nexists"]="∄",["\\in"]="∈",["\\notin"]="∉",["\\emptyset"]="∅",["\\varnothing"]="∅",["\\subset"]="⊂",["\\supset"]="⊃",["\\subseteq"]="⊆",["\\supseteq"]="⊇",["\\cup"]="∪",["\\cap"]="∩",["\\vee"]="∨",["\\wedge"]="∧",["\\perp"]="⊥",["\\parallel"]="∥",["\\angle"]="∠",["\\equiv"]="≡",["\\propto"]="∝",["\\mp"]="∓",["\\cdotp"]="·",["\\ldots"]="…",["\\cdots"]="⋯",["\\hbar"]="ℏ",["\\ell"]="ℓ",["\\aleph"]="ℵ",["\\chi"]="χ",["\\psi"]="ψ",["\\zeta"]="ζ",["\\eta"]="η",["\\kappa"]="κ",["\\xi"]="ξ",["\\upsilon"]="υ",["\\Gamma"]="Γ",["\\Theta"]="Θ",["\\Lambda"]="Λ",["\\Xi"]="Ξ",["\\Pi"]="Π",["\\Psi"]="Ψ"
    };
    public static string? ToUnicode(string command) => glyphs.TryGetValue(command, out var value) ? value : command.Length == 1 && command != "\\" ? command : null;
}

/// <summary>Offline CPU symbol recognition using the converted, bundled deTeXt model. Scores rank candidates, not certainty.</summary>
public sealed class MathRecognitionService : IDisposable
{
    public static MathRecognitionService Shared { get; } = new();
    private InferenceSession? model;
    private string[]? labels;
    private readonly SemaphoreSlim gate = new(1,1);
    private System.Threading.Timer? idleTimer;
    private int disposed;
    private static readonly TimeSpan idleLimit = TimeSpan.FromMinutes(3);
    public bool IsModelLoaded => Volatile.Read(ref model) != null;
    public Task<IReadOnlyList<MathSymbolCandidate>> RecognizeAsync(IReadOnlyList<DrawingElement> strokes, CancellationToken ct) => RecognizeAsync(strokes.Where(x => x.Kind == "stroke").Select(x => x.Points.ToArray()).ToList(), ct);
    public async Task<IReadOnlyList<MathSymbolCandidate>> RecognizeAsync(List<InkPoint[]> strokes, CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref disposed) != 0, this);
        cancellationToken.ThrowIfCancellationRequested(); var pixels = Rasterize(strokes); await gate.WaitAsync(cancellationToken);
        try
        {
            ObjectDisposedException.ThrowIf(Volatile.Read(ref disposed) != 0, this);
            SetIdleTimer(Timeout.InfiniteTimeSpan);
            return await Task.Run<IReadOnlyList<MathSymbolCandidate>>(() =>
            {
                cancellationToken.ThrowIfCancellationRequested(); Load();
                var data = new float[3 * 200 * 300];
                for(var c=0;c<3;c++) Array.Copy(pixels,0,data,c*60000,60000);
                var tensor = new DenseTensor<float>(data, new[] { 1, 3, 200, 300 });
                using var options = new RunOptions(); using var registration = cancellationToken.Register(() => options.Terminate = true);
                using var results = model!.Run(new[] { NamedOnnxValue.CreateFromTensor("drawing", tensor) }, new[] { "classLabelProbs" }, options);
                cancellationToken.ThrowIfCancellationRequested();
                var output = results.SingleOrDefault(x => x.Name == "classLabelProbs" && x.AsTensor<float>().Length == labels!.Length) ?? throw new InvalidDataException("The offline maths model returned an unexpected score array.");
                var scores = output.AsTensor<float>().ToArray();
                if (scores.Any(x => !float.IsFinite(x))) throw new InvalidDataException("The offline maths model returned invalid scores.");
                // The converted network includes its original softmax. Validate, do not silently reinterpret logits.
                if (scores.Any(x => x < 0) || Math.Abs(scores.Sum(x => (double)x) - 1) > .02) throw new InvalidDataException("The offline maths model did not return probabilities.");
                var catalog = MathSymbolCatalog.ById;
                return scores.Select((score,i) => new MathSymbolCandidate(labels![i], catalog[labels[i]].Command, score)).OrderByDescending(x=>x.Probability).ThenBy(x=>x.Label).Take(20).ToArray();
            }, cancellationToken);
        }
        catch (OnnxRuntimeException) when(cancellationToken.IsCancellationRequested) { throw new OperationCanceledException(cancellationToken); }
        catch (OnnxRuntimeException ex) { throw new InvalidOperationException("The offline maths model could not run. Reinstall the app or try a smaller symbol.", ex); }
        finally
        {
            if (Volatile.Read(ref disposed) != 0) ReleaseModel();
            else if (model != null) SetIdleTimer(idleLimit);
            gate.Release();
        }
    }
    private void Load()
    {
        if (model != null) return; var root = Path.Combine(AppContext.BaseDirectory,"Resources","MathSymbols");
        var modelPath=Path.Combine(root,"deTeX.onnx"); var classPath=Path.Combine(root,"classes.json");
        if (!File.Exists(modelPath) || !File.Exists(classPath)) throw new FileNotFoundException("The offline maths model is missing. Reinstall the app.");
        var classLabels = JsonSerializer.Deserialize<string[]>(File.ReadAllText(classPath)) ?? throw new InvalidDataException("The offline maths class labels are invalid.");
        if (classLabels.Length != 1098 || classLabels.Any(string.IsNullOrEmpty) || classLabels.Distinct().Count() != classLabels.Length || classLabels.Any(x=>!MathSymbolCatalog.ById.ContainsKey(x))) throw new InvalidDataException("The offline maths class labels do not match the bundled 1,098 symbols.");
        using var configuration = new SessionOptions { GraphOptimizationLevel = GraphOptimizationLevel.ORT_ENABLE_ALL, ExecutionMode = ExecutionMode.ORT_SEQUENTIAL, IntraOpNumThreads = Math.Max(1, Math.Min(2, Environment.ProcessorCount)), InterOpNumThreads = 1 };
        configuration.AddSessionConfigEntry("session.intra_op.allow_spinning", "0");
        configuration.AddSessionConfigEntry("session.inter_op.allow_spinning", "0");
        var loaded = new InferenceSession(modelPath, configuration);
        try
        {
            if (loaded.InputMetadata.Count != 1 || !loaded.InputMetadata.TryGetValue("drawing",out var input) || input.ElementType != typeof(float) || !input.Dimensions.SequenceEqual(new[] {1,3,200,300}) || !loaded.OutputMetadata.TryGetValue("classLabelProbs",out var output) || output.ElementType != typeof(float) || !output.Dimensions.SequenceEqual(new[] {1,1098})) throw new InvalidDataException("The offline maths model does not match the bundled input and symbol classes.");
            idleTimer ??= new System.Threading.Timer(_=>TryReleaseIdleResources(),null,Timeout.InfiniteTimeSpan,Timeout.InfiniteTimeSpan);
            model = loaded; labels = classLabels;
        }
        catch { loaded.Dispose(); throw; }
    }
    internal static float[] Rasterize(List<InkPoint[]> strokes)
    {
        ArgumentNullException.ThrowIfNull(strokes);
        if (strokes.Any(x=>x==null) || strokes.Count > 2048 || strokes.Sum(x => (long)x.Length) > 100000) throw new ArgumentException("Select one symbol using at most 2,048 strokes and 100,000 points.");
        var points=strokes.SelectMany(x=>x).ToArray(); if(points.Length==0) throw new ArgumentException("Draw or select one handwritten symbol first.");
        if(points.Any(p=>!double.IsFinite(p.X)||!double.IsFinite(p.Y)||Math.Abs(p.X)>1e9||Math.Abs(p.Y)>1e9)) throw new ArgumentException("The symbol has invalid coordinates.");
        var minX=points.Min(p=>p.X);var minY=points.Min(p=>p.Y);var spanX=points.Max(p=>p.X)-minX;var spanY=points.Max(p=>p.Y)-minY;
        if(Math.Max(spanX,spanY)<=1e-6) throw new ArgumentException("The symbol has no visible stroke length.");
        var scale=Math.Min(250/Math.Max(spanX,1e-6),(200/1.2)/Math.Max(spanY,1e-6));var ox=(300-spanX*scale)/2;var oy=(200-spanY*scale)/2;
        Point Normalize(InkPoint p)=>new((p.X-minX)*scale+ox,(p.Y-minY)*scale+oy);
        var visual=new DrawingVisual();using(var dc=visual.RenderOpen())
        {
            dc.DrawRectangle(Brushes.Black,null,new Rect(0,0,300,200));var pen=new Pen(Brushes.White,5){StartLineCap=PenLineCap.Round,EndLineCap=PenLineCap.Round,LineJoin=PenLineJoin.Round};
            foreach(var stroke in strokes.Where(s=>s.Length>0))
            { if(stroke.Length==1) dc.DrawEllipse(Brushes.White,null,Normalize(stroke[0]),2.5,2.5);else { var path=new StreamGeometry();using(var context=path.Open()){context.BeginFigure(Normalize(stroke[0]),false,false);context.PolyLineTo(stroke.Skip(1).Select(Normalize).ToArray(),true,false);}dc.DrawGeometry(null,pen,path); } }
        }
        var bitmap=new RenderTargetBitmap(300,200,96,96,PixelFormats.Pbgra32);bitmap.Render(visual);var bgra=new byte[240000];bitmap.CopyPixels(bgra,1200,0);var pixels=new float[60000];for(var i=0;i<pixels.Length;i++)pixels[i]=bgra[i*4];return pixels;
    }
    /// <summary>Nonblocking: an active recognition retains its model until it finishes. No model is loaded by this call.</summary>
    public bool TryReleaseIdleResources()
    {
        if (!gate.Wait(0)) return false;
        try { SetIdleTimer(Timeout.InfiniteTimeSpan); ReleaseModel(); return true; }
        finally { gate.Release(); }
    }
    private void SetIdleTimer(TimeSpan due) { try { idleTimer?.Change(due,Timeout.InfiniteTimeSpan); } catch(ObjectDisposedException) when(Volatile.Read(ref disposed)!=0) { } }
    private void ReleaseModel() { var previous=model; model=null; labels=null; previous?.Dispose(); }
    public void Dispose()
    {
        if(Interlocked.Exchange(ref disposed,1)!=0)return;
        // Keep the managed gate valid for already waiting operations; those finish with ObjectDisposedException.
        TryReleaseIdleResources(); idleTimer?.Dispose();
    }
}

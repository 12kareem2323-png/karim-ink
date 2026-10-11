using System.Diagnostics;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
namespace KarimEldamatyWindows;

/// Retained WPF drawing: committed artwork is cached independently of live stylus packets.
public sealed class BoardCanvas : FrameworkElement
{
    private readonly VisualCollection visuals;
    private readonly DrawingVisual background = new();
    private readonly ContainerVisual committed = new();
    private readonly DrawingVisual ink = new();
    private readonly DrawingVisual previewVisual = new();
    private readonly DrawingVisual overlay = new();
    private DrawingGroup activeInk = new();
    private DrawingSession session = new();
    private readonly Dictionary<Guid,CacheEntry> cache = [];
    private readonly DocumentSceneIndex scene = new();
    private int indexedRevision=-1,cacheClock;
    private Guid indexedBoard;
    private string indexedBackground="";
    private long cachedSamples;
    private const int MaximumCacheElements=1200;
    private const long MaximumCacheSamples=180000;
    private DrawingElement? stroke,preview;
    private readonly List<InkPoint> rawSamples = [];
    private readonly AdaptiveInkFilter filter = new();
    private List<DrawingElement>? selectionPreview;
    private List<DrawingElement>? originalSelection;
    private Point? startWorld,lastWorld;
    private Point startScreen,panOrigin,holdAnchor;
    private Rect selectionBounds;
    private int resizeCorner=-1;
    private readonly List<Point> lasso = [];
    private bool down,panning,spaceHeld,eraserGesture,moved,held;
    private string gestureTool="Draw";
    private double lastTimestamp;
    private bool eraserChanged,eraserCheckpointTaken;
    private Point? lastEraserPoint;
    private int mouseSuppressionUntil;
    private Point? hover;
    private readonly DispatcherTimer holdTimer;
    private readonly DispatcherTimer animationTimer;
    private readonly DispatcherTimer telemetryTimer;
    private bool telemetryPending;
    private Guid? animatedId;
    private string[] animationFrames=[];
    private DateTime animationStart;
    private readonly Dictionary<int,Point> touches=[];
    private Point touchCenter;
    private double touchDistance;
    public event Action<DrawingElement>? LineStraightened;
    public event Action<Point>? TextRequested;
    public event Action<string>? FileDropRequested;
    public DrawingSession Session
    {
        get=>session;
        set {if(ReferenceEquals(session,value))return;FinishStroke();session.Changed-=SessionChanged;session=value ?? throw new ArgumentNullException(nameof(value));session.Changed+=SessionChanged;indexedRevision=-1;ClearCache();Refresh();}
    }
    public BoardCanvas()
    {
        visuals=new(this){background,committed,ink,previewVisual,overlay};Focusable=true;ClipToBounds=true;AllowDrop=true;SnapsToDevicePixels=false;
        holdTimer=new DispatcherTimer(DispatcherPriority.Input){Interval=TimeSpan.FromMilliseconds(500)};holdTimer.Tick+=(_,_)=>CorrectHeldStroke();
        animationTimer=new DispatcherTimer(DispatcherPriority.Background){Interval=TimeSpan.FromMilliseconds(90)};animationTimer.Tick+=(_,_)=>AdvanceSymbolAnimation();
        telemetryTimer=new DispatcherTimer(DispatcherPriority.Background){Interval=TimeSpan.FromMilliseconds(33)};telemetryTimer.Tick+=(_,_)=>{telemetryTimer.Stop();if(telemetryPending){telemetryPending=false;session.NotifyInputChanged();}};
        session.Changed+=SessionChanged;SizeChanged+=(_,_)=>Refresh();LostKeyboardFocus+=(_,_)=>FinishStroke();Unloaded+=(_,_)=>{FinishStroke();holdTimer.Stop();animationTimer.Stop();telemetryTimer.Stop();};
        RenderOptions.SetEdgeMode(this,EdgeMode.Unspecified);RenderOptions.SetBitmapScalingMode(this,BitmapScalingMode.HighQuality);
    }
    protected override int VisualChildrenCount=>visuals.Count;
    protected override Visual GetVisualChild(int index)=>visuals[index];
    protected override Size MeasureOverride(Size available)=>new(double.IsInfinity(available.Width)?900:available.Width,double.IsInfinity(available.Height)?600:available.Height);
    protected override void OnRender(DrawingContext dc){base.OnRender(dc);dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(226,232,238)),null,new Rect(RenderSize));}
    public Point WorldPoint(Point screen)=>new((screen.X-session.Offset.X)/session.Zoom,(screen.Y-session.Offset.Y)/session.Zoom);
    public Point ScreenPoint(Point world)=>new(world.X*session.Zoom+session.Offset.X,world.Y*session.Zoom+session.Offset.Y);
    public void FitBoard()
    {
        if(ActualWidth<=0||ActualHeight<=0)return;FinishStroke();session.Zoom=Math.Clamp(Math.Min((ActualWidth-64)/session.Board.Width,(ActualHeight-64)/session.Board.Height),.02,20);session.Offset=new((ActualWidth-session.Board.Width*session.Zoom)/2,(ActualHeight-session.Board.Height*session.Zoom)/2);Refresh();session.NotifyViewChanged();
    }
    public void ZoomAt(Point screen,double factor)
    {
        var world=WorldPoint(screen);session.Zoom=Math.Clamp(session.Zoom*factor,.02,40);session.Offset=new(screen.X-world.X*session.Zoom,screen.Y-world.Y*session.Zoom);Refresh();session.NotifyViewChanged();
    }
    private void SessionChanged(){if(!Dispatcher.CheckAccess()){Dispatcher.BeginInvoke(Refresh);return;}Refresh();}
    public void Refresh()
    {
        if(ActualWidth<=0||ActualHeight<=0)return;session.Zoom=Math.Clamp(double.IsFinite(session.Zoom)?session.Zoom:1,.02,40);
        var matrix=new Matrix(session.Zoom,0,0,session.Zoom,session.Offset.X,session.Offset.Y);var transform=new MatrixTransform(matrix);transform.Freeze();background.Transform=committed.Transform=ink.Transform=previewVisual.Transform=transform;
        var sheet=new Rect(0,0,session.Board.Width,session.Board.Height);var view=new Rect(WorldPoint(new(0,0)),WorldPoint(new(ActualWidth,ActualHeight)));
        using(var dc=background.RenderOpen()){dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(223,230,237)),null,new Rect(WorldPoint(new()),WorldPoint(new(ActualWidth,ActualHeight))));if(!view.IsEmpty)BoardRenderer.DrawBackground(dc,session.Board,view,session.Zoom);dc.DrawRectangle(null,new Pen(new InkColor(.45,.50,.56,.30).Brush(),1/session.Zoom),sheet);}
        Reindex();var visible=scene.Query(view);var seen=visible.Select(e=>e.Id).ToHashSet();var desired=new List<DrawingVisual>(visible.Count);var movingIds=selectionPreview?.Select(e=>e.Id).ToHashSet();
        foreach(var e in visible){if(movingIds?.Contains(e.Id)==true)continue;var signature=scene.Signature(e.Id);if(!cache.TryGetValue(e.Id,out var entry)||entry.Signature!=signature){if(entry is not null){cachedSamples-=entry.Samples;cache.Remove(e.Id);}var visual=new DrawingVisual();using(var dc=visual.RenderOpen())dc.DrawDrawing(BoardRenderer.BuildElement(e,session.Board));entry=new(visual,signature,e.Points.Count,++cacheClock);cache[e.Id]=entry;cachedSamples+=e.Points.Count;}entry.LastUsed=++cacheClock;entry.Visual.Opacity=e.Id==animatedId?0:1;desired.Add(entry.Visual);}
        var same=committed.Children.Count==desired.Count;if(same)for(var i=0;i<desired.Count;i++)if(!ReferenceEquals(committed.Children[i],desired[i])){same=false;break;}
        if(!same){committed.Children.Clear();foreach(var visual in desired)committed.Children.Add(visual);}
        EvictCache(seen);DrawPreview();DrawOverlay();
    }
    private void Reindex()
    {
        if(indexedBoard!=session.Board.Id||indexedBackground!=session.Board.Background){ClearCache();scene.Clear();indexedRevision=-1;}
        if(indexedRevision==session.Revision)return;scene.Synchronize(session.Board);
        foreach(var id in cache.Keys.Where(id=>!scene.Contains(id)).ToArray()){cachedSamples-=cache[id].Samples;cache.Remove(id);}
        indexedBoard=session.Board.Id;indexedBackground=session.Board.Background;indexedRevision=session.Revision;
    }
    private void ClearCache(){committed.Children.Clear();cache.Clear();cachedSamples=0;}
    private void EvictCache(HashSet<Guid> visible){foreach(var id in cache.Where(pair=>!visible.Contains(pair.Key)).OrderBy(pair=>pair.Value.LastUsed).Select(pair=>pair.Key).ToArray()){if(cache.Count<=MaximumCacheElements&&cachedSamples<=MaximumCacheSamples)break;var item=cache[id];cachedSamples-=item.Samples;cache.Remove(id);}}
    private void DrawPreview()
    {
        using(var dc=previewVisual.RenderOpen()){
            if(preview is not null)BoardRenderer.DrawElement(dc,preview,session.Board);
            if(selectionPreview is not null)foreach(var e in selectionPreview)BoardRenderer.DrawElement(dc,e,session.Board);
            if(down&&(gestureTool is "Select" or "Lasso")&&selectionPreview is null&&startWorld is not null&&lastWorld is not null){var pen=BoardRenderer.MakePen(InkColor.Blue,1/session.Zoom,"Dashed");if(gestureTool=="Select")dc.DrawRectangle(InkColor.Blue.Brush(.07),pen,new(startWorld.Value,lastWorld.Value));else if(lasso.Count>1){var g=new StreamGeometry();using(var c=g.Open()){c.BeginFigure(lasso[0],true,true);c.PolyLineTo(lasso.Skip(1).ToArray(),true,true);}dc.DrawGeometry(InkColor.Blue.Brush(.07),pen,g);}}
        }
    }
    private void DrawOverlay()
    {
        using(var dc=overlay.RenderOpen()){
            if(session.SelectedIds.Count>0){var selected=selectionPreview is null?session.Board.Elements.Where(e=>session.SelectedIds.Contains(e.Id)).ToList():selectionPreview.Concat(session.Board.Elements.Where(e=>e.Locked&&session.SelectedIds.Contains(e.Id))).ToList();var bounds=BoundsOf(selected);if(!bounds.IsEmpty){var a=ScreenPoint(bounds.TopLeft);var b=ScreenPoint(bounds.BottomRight);var r=new Rect(a,b);dc.DrawRectangle(null,BoardRenderer.MakePen(InkColor.Blue,1.5,"Dashed"),r);foreach(var p in DrawingMath.Corners(r))dc.DrawRectangle(Brushes.White,new Pen(InkColor.Blue.Brush(),1.5),new(p.X-4,p.Y-4,8,8));}}
            if(hover is {} point&&!panning){var diameter=Math.Max(5,session.Settings.Width(session.LivePressure??1)*session.Zoom);var brush=session.Tool=="Eraser"?new InkColor(.83,.23,.26).Brush():BoardRenderer.VisibleColor(session.Color,session.Board).Brush(.8);var pen=new Pen(brush,1);dc.DrawEllipse(null,pen,point,Math.Min(200,diameter)/2,Math.Min(200,diameter)/2);dc.DrawEllipse(brush,null,point,1.1,1.1);}
            if(session.ShowRuler)DrawRuler(dc);if(session.ShowProtractor)DrawProtractor(dc);
        }
    }
    private void DrawRuler(DrawingContext dc){var r=new Rect(26,26,Math.Max(100,Math.Min(950,ActualWidth-52)),66);dc.DrawRoundedRectangle(new InkColor(.92,.96,1,.9).Brush(),new Pen(InkColor.Blue.Brush(.6),1),r,4,4);var mmToScreen=session.Board.DrawingPoints(1)*session.Zoom;var step=1d;while(step*mmToScreen<8)step*=10;for(var mm=0d;mm*mmToScreen<r.Width;mm+=step){var x=r.Left+mm*mmToScreen;var major=Math.Abs(mm/10-Math.Round(mm/10))<.001;dc.DrawLine(new Pen(InkColor.Blue.Brush(),1),new(x,r.Top),new(x,r.Top+(major?25:13)));if(major)BoardRenderer.DrawText(dc,BoardRenderer.Formatted(mm),new(x+2,r.Top+27),12,InkColor.Blue);}BoardRenderer.DrawText(dc,$"mm  •  scale 1:{BoardRenderer.Formatted(session.Board.ScaleDenominator)}",new(r.Left+10,r.Bottom-17),11,InkColor.Blue);}
    private void DrawProtractor(DrawingContext dc){var radius=Math.Max(50,Math.Min(190,Math.Min(ActualWidth,ActualHeight)/3));var center=new Point(ActualWidth/2,ActualHeight/2+radius/3);var path=new StreamGeometry();using(var g=path.Open()){g.BeginFigure(new(center.X-radius,center.Y),true,true);g.ArcTo(new(center.X+radius,center.Y),new(radius,radius),0,false,SweepDirection.Clockwise,true,false);}dc.DrawGeometry(InkColor.Teal.Brush(.1),new Pen(InkColor.Teal.Brush(.7),1),path);for(var degrees=0;degrees<=180;degrees+=5){var angle=degrees*Math.PI/180;var inner=radius-(degrees%10==0?20:10);dc.DrawLine(new Pen(InkColor.Teal.Brush(.7),1),new(center.X+Math.Cos(angle)*inner,center.Y-Math.Sin(angle)*inner),new(center.X+Math.Cos(angle)*radius,center.Y-Math.Sin(angle)*radius));if(degrees%30==0)BoardRenderer.DrawText(dc,degrees+"°",new(center.X+Math.Cos(angle)*(radius-38)-10,center.Y-Math.Sin(angle)*(radius-38)-8),12,InkColor.Teal);}dc.DrawEllipse(InkColor.Teal.Brush(),null,center,3,3);}
    private static Rect BoundsOf(IEnumerable<DrawingElement> elements){var r=Rect.Empty;foreach(var e in elements)r.Union(e.Bounds);return r;}
    protected override void OnMouseDown(MouseButtonEventArgs e)
    {
        base.OnMouseDown(e);if(e.StylusDevice is not null||session.PenActive||Environment.TickCount-mouseSuppressionUntil<0){e.Handled=true;return;}Focus();var p=e.GetPosition(this);
        if(e.ChangedButton==MouseButton.Middle||e.ChangedButton==MouseButton.Left&&spaceHeld){StartPan(p);CaptureMouse();e.Handled=true;return;}
        if(e.ChangedButton==MouseButton.Right){ShowContext(p);e.Handled=true;return;}
        if(e.ChangedButton!=MouseButton.Left)return;if(e.ClickCount==2&&session.Tool=="Select"){var target=Hit(WorldPoint(p));if(target?.Kind=="text"){EditText(target.Points[0].Point,target);e.Handled=true;return;}}
        BeginInput(p,false);if(down)CaptureMouse();e.Handled=true;
    }
    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);if(e.StylusDevice is not null||session.PenActive||Environment.TickCount-mouseSuppressionUntil<0)return;var p=e.GetPosition(this);hover=p;if(panning){UpdatePan(p);return;}if(down&&e.LeftButton==MouseButtonState.Pressed)MoveInput(p,null);else DrawOverlay();
    }
    protected override void OnMouseUp(MouseButtonEventArgs e){base.OnMouseUp(e);if(e.StylusDevice is not null)return;if(panning){panning=false;ReleaseMouseCapture();return;}if(e.ChangedButton==MouseButton.Left&&down){MoveInput(e.GetPosition(this),null);FinishStroke();ReleaseMouseCapture();e.Handled=true;}}
    protected override void OnLostMouseCapture(MouseEventArgs e){base.OnLostMouseCapture(e);if(down&&!session.PenActive)FinishStroke();panning=false;}
    protected override void OnMouseLeave(MouseEventArgs e){base.OnMouseLeave(e);hover=null;DrawOverlay();}
    protected override void OnMouseWheel(MouseWheelEventArgs e){base.OnMouseWheel(e);FinishStroke();if(Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)){session.Offset=new(session.Offset.X+e.Delta*.5,session.Offset.Y);Refresh();session.NotifyViewChanged();}else ZoomAt(e.GetPosition(this),Math.Pow(1.15,e.Delta/120d));e.Handled=true;}
    private void ActivatePen(StylusDevice device)
    {
        if(device.TabletDevice.Type==TabletDeviceType.Touch)return;
        var tablet=device.TabletDevice;var runtime=$"{tablet.Id}:{device.Id}";
        if(!session.PenActive&&down)FinishStroke();
        if(session.InputCapabilities.RuntimeDeviceId!=runtime){var hardware=tablet.TabletHardwareCapabilities;var properties=tablet.SupportedStylusPointProperties;session.InputCapabilities=new(){DeviceName=tablet.Name,PenName=device.Name,DeviceKey=PenInputCapabilities.ProfileKey(tablet.ProductId,tablet.Name,device.Name),RuntimeDeviceId=runtime,IdentitySource=string.IsNullOrWhiteSpace(tablet.ProductId)?"Driver name fallback; identical devices may share a profile":"Driver product identifier and names; may change after driver reinstall",PressureSupported=hardware.HasFlag(TabletHardwareCapabilities.SupportsPressure),PhysicalPenIdentityAvailable=hardware.HasFlag(TabletHardwareCapabilities.StylusHasPhysicalIds),HoverSupported=hardware.HasFlag(TabletHardwareCapabilities.HardProximity),TiltXSupported=properties.Any(p=>p.Id==StylusPointProperties.XTiltOrientation.Id),TiltYSupported=properties.Any(p=>p.Id==StylusPointProperties.YTiltOrientation.Id),EraserObserved=device.Inverted};session.InputDeviceKey=session.InputCapabilities.DeviceKey;session.NotifyInputChanged();}
        session.PenActive=true;if(device.Inverted)session.InputCapabilities.EraserObserved=true;
        foreach(var touch in TouchesCaptured.ToArray())touch.Capture(null);touches.Clear();mouseSuppressionUntil=Environment.TickCount+300;
    }
    protected override void OnStylusInRange(StylusEventArgs e){base.OnStylusInRange(e);ActivatePen(e.StylusDevice);}
    protected override void OnStylusOutOfRange(StylusEventArgs e){base.OnStylusOutOfRange(e);if(e.StylusDevice.TabletDevice.Type==TabletDeviceType.Touch)return;FinishStroke();session.PenActive=false;session.LivePressure=session.LiveRawPressure=null;session.NotifyInputChanged();hover=null;DrawOverlay();}
    protected override void OnStylusDown(StylusDownEventArgs e)
    {
        base.OnStylusDown(e);if(e.StylusDevice.TabletDevice.Type==TabletDeviceType.Touch)return;Focus();ActivatePen(e.StylusDevice);var p=e.GetPosition(this);eraserGesture=e.StylusDevice.Inverted;BeginInput(p,true);if(down){CaptureStylus();var samples=e.GetStylusPoints(this);if(samples.Count>0)AppendStylusSamples(samples);}e.Handled=true;
    }
    protected override void OnStylusMove(StylusEventArgs e)
    {
        base.OnStylusMove(e);if(e.StylusDevice.TabletDevice.Type==TabletDeviceType.Touch)return;mouseSuppressionUntil=Environment.TickCount+250;hover=e.GetPosition(this);if(panning){UpdatePan(hover.Value);e.Handled=true;return;}if(down){var samples=e.GetStylusPoints(this);if(gestureTool=="Draw"&&!eraserGesture)AppendStylusSamples(samples);else{if(samples.Count>0)UpdateTelemetry(samples[^1]);MoveInput(hover.Value,null);}}else {var samples=e.GetStylusPoints(this);if(samples.Count>0)UpdateTelemetry(samples[^1]);DrawOverlay();}e.Handled=true;
    }
    protected override void OnStylusUp(StylusEventArgs e){base.OnStylusUp(e);if(e.StylusDevice.TabletDevice.Type==TabletDeviceType.Touch)return;if(down){var samples=e.GetStylusPoints(this);if(gestureTool=="Draw"&&!eraserGesture)AppendStylusSamples(samples);else MoveInput(e.GetPosition(this),null);FinishStroke();}panning=false;ReleaseStylusCapture();if(!session.InputCapabilities.HoverSupported){session.PenActive=false;session.LivePressure=session.LiveRawPressure=null;session.NotifyInputChanged();}mouseSuppressionUntil=Environment.TickCount+250;e.Handled=true;}
    protected override void OnLostStylusCapture(StylusEventArgs e){base.OnLostStylusCapture(e);if(down)FinishStroke();panning=false;}
    protected override void OnStylusButtonDown(StylusButtonEventArgs e)
    {
        base.OnStylusButtonDown(e);if(e.StylusDevice.TabletDevice.Type==TabletDeviceType.Touch||e.StylusButton.Guid==StylusPointProperties.TipButton.Id)return;ActivatePen(e.StylusDevice);session.InputCapabilities.BarrelButtonObserved=true;session.NotifyInputChanged();
        switch(session.BarrelButtonAction){case "Pan":StartPan(e.GetPosition(this));CaptureStylus();break;case "Context menu":FinishStroke();ShowContext(e.GetPosition(this));break;}e.Handled=true;
    }
    protected override void OnStylusButtonUp(StylusButtonEventArgs e){base.OnStylusButtonUp(e);if(e.StylusButton.Guid==StylusPointProperties.TipButton.Id)return;if(panning){panning=false;ReleaseStylusCapture();Cursor=spaceHeld?Cursors.Hand:Cursors.Arrow;}e.Handled=true;}
    private static double TiltValue(StylusPoint sample,StylusPointProperty property)
    {
        if(!sample.Description.HasProperty(property))return 0;var info=sample.Description.GetPropertyInfo(property);var value=sample.GetPropertyValue(property);double normalized;
        if(info.Unit==StylusPointPropertyUnit.Degrees&&info.Resolution>0)normalized=value/info.Resolution/90d;
        else if(info.Unit==StylusPointPropertyUnit.Radians&&info.Resolution>0)normalized=value/info.Resolution/(Math.PI/2);
        else{var half=(info.Maximum-(double)info.Minimum)/2;normalized=half>0?(value-(info.Maximum+(double)info.Minimum)/2)/half:0;}return Math.Clamp(normalized,-1,1);
    }
    private void UpdateTelemetry(StylusPoint sample)
    {
        var capabilities=session.InputCapabilities;capabilities.TiltXSupported=sample.Description.HasProperty(StylusPointProperties.XTiltOrientation);capabilities.TiltYSupported=sample.Description.HasProperty(StylusPointProperties.YTiltOrientation);capabilities.DeliveredSamples++;
        session.LiveRawPressure=capabilities.PressureSupported?Math.Clamp(sample.PressureFactor,0,1):null;session.LivePressure=session.LiveRawPressure is {} raw?DrawingMath.CalibratedPressure(raw,session.ActivationPressure):null;session.LiveTilt=new(TiltValue(sample,StylusPointProperties.XTiltOrientation),TiltValue(sample,StylusPointProperties.YTiltOrientation));
        telemetryPending=true;if(!telemetryTimer.IsEnabled)telemetryTimer.Start();
    }
    private void AppendStylusSamples(StylusPointCollection samples)
    {
        if(!down||gestureTool!="Draw"||eraserGesture||stroke is null)return;var now=Stopwatch.GetTimestamp()/(double)Stopwatch.Frequency;var dt=Math.Clamp((now-lastTimestamp)/Math.Max(1,samples.Count),.0001,.05);for(int i=0;i<samples.Count;i++){var p=samples[i];UpdateTelemetry(p);var screen=new Point(p.X,p.Y);hover=screen;var world=WorldPoint(screen);var time=now-(samples.Count-1-i)*dt;var ip=new InkPoint(world.X,world.Y,session.InputCapabilities.PressureSupported?Math.Clamp(p.PressureFactor,0,1):1){RawPressure=session.InputCapabilities.PressureSupported?Math.Clamp(p.PressureFactor,0,1):null,TiltX=session.LiveTilt.X,TiltY=session.LiveTilt.Y,InputDeviceKey=session.InputDeviceKey};AppendInk(ip,time);}DrawOverlay();
    }
    private void BeginInput(Point screen,bool stylus)
    {
        if(down)FinishStroke();startScreen=screen;startWorld=lastWorld=WorldPoint(screen);lastTimestamp=Stopwatch.GetTimestamp()/(double)Stopwatch.Frequency;gestureTool=eraserGesture?"Eraser":session.Tool;down=true;moved=false;held=false;resizeCorner=-1;hover=screen;rawSamples.Clear();filter.Reset();lasso.Clear();stroke=preview=null;selectionPreview=originalSelection=null;
        if(!stylus){session.LivePressure=session.LiveRawPressure=null;session.LiveTilt=default;session.InputDeviceKey=null;session.InputCapabilities=new();session.NotifyInputChanged();}
        if(gestureTool is not ("Select" or "Lasso")&&session.SelectedIds.Count>0){session.SelectedIds.Clear();session.NotifyViewChanged();}
        if(gestureTool=="Draw"&&!eraserGesture&&session.PendingSymbolId is {} symbol){var p=Snap(startWorld.Value);var e=new DrawingElement{Kind="symbol",Text=symbol.StartsWith("catalog:")?symbol:"catalog:"+symbol,Points=[new(p.X,p.Y),new(p.X+240,p.Y+180)],Color=session.Color,Width=session.Settings.MaxWidth};down=false;session.PendingSymbolId=null;session.Commit(e);session.SelectedIds=[e.Id];session.NotifyViewChanged();StartSymbolAnimation(e);session.Status("Symbol placed. Use Select to move and resize it.");return;}
        if(gestureTool=="Text"){down=false;if(TextRequested is not null)TextRequested(Snap(startWorld.Value));else EditText(Snap(startWorld.Value));return;}
        if(gestureTool=="Select"){
            selectionBounds=BoundsOf(session.Board.Elements.Where(e=>session.SelectedIds.Contains(e.Id)));if(!selectionBounds.IsEmpty)resizeCorner=Array.FindIndex(DrawingMath.Corners(selectionBounds),p=>(ScreenPoint(p)-screen).Length<=10);
            var hit=Hit(startWorld.Value);if(resizeCorner>=0){originalSelection=session.Board.Elements.Where(e=>session.SelectedIds.Contains(e.Id)&&!e.Locked).Select(BoardCodec.Clone).ToList();selectionPreview=originalSelection.Select(BoardCodec.Clone).ToList();}
            else if(hit is not null){if(Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)){if(!session.SelectedIds.Add(hit.Id))session.SelectedIds.Remove(hit.Id);}else if(!session.SelectedIds.Contains(hit.Id))session.SelectedIds=[hit.Id];originalSelection=session.Board.Elements.Where(e=>session.SelectedIds.Contains(e.Id)&&!e.Locked).Select(BoardCodec.Clone).ToList();selectionPreview=originalSelection.Select(BoardCodec.Clone).ToList();}
            else if(!Keyboard.Modifiers.HasFlag(ModifierKeys.Shift))session.SelectedIds.Clear();Refresh();return;
        }
        if(gestureTool=="Lasso"){if(!Keyboard.Modifiers.HasFlag(ModifierKeys.Shift))session.SelectedIds.Clear();lasso.Add(startWorld.Value);DrawOverlay();return;}
        if(gestureTool=="Eraser"){eraserChanged=eraserCheckpointTaken=false;lastEraserPoint=null;Erase(startWorld.Value);return;}
        var first=gestureTool=="Draw"?startWorld.Value:Snap(startWorld.Value);startWorld=lastWorld=first;stroke=new(){Kind=Kind(gestureTool),Color=session.Color,Pen=session.Pen,Width=session.Settings.MaxWidth,BrushSettings=BoardCodec.Clone(session.Settings),Dash=session.Dash,Fill=session.FillShapes};
        if(gestureTool=="Draw"){
            activeInk=new();if(stroke.Pen=="Highlighter")activeInk.Opacity=stroke.EffectiveBrushSettings.Opacity*stroke.EffectiveBrushSettings.MaxOpacity;using(var dc=ink.RenderOpen())dc.DrawDrawing(activeInk);if(!stylus)AppendInk(new(first.X,first.Y),lastTimestamp);holdAnchor=first;holdTimer.Stop();if(session.AutoCorrect)holdTimer.Start();
        }else{stroke.Points=[new(first.X,first.Y),new(first.X,first.Y)];preview=stroke;DrawPreview();}
    }
    private void MoveInput(Point screen,InkPoint? sample)
    {
        if(!down)return;var world=WorldPoint(screen);lastWorld=world;if((screen-startScreen).Length>3)moved=true;
        if(gestureTool=="Eraser"){Erase(world);return;}
        if(gestureTool=="Select"){
            if(selectionPreview is not null&&originalSelection is not null&&startWorld is {} start){selectionPreview=originalSelection.Select(BoardCodec.Clone).ToList();if(resizeCorner>=0){var opposite=DrawingMath.Corners(selectionBounds)[(resizeCorner+2)%4];var corner=DrawingMath.Corners(selectionBounds)[resizeCorner];var sx=Math.Abs(corner.X-opposite.X)<.1?1:(Snap(world).X-opposite.X)/(corner.X-opposite.X);var sy=Math.Abs(corner.Y-opposite.Y)<.1?1:(Snap(world).Y-opposite.Y)/(corner.Y-opposite.Y);if(Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)){var size=Math.Max(Math.Abs(sx),Math.Abs(sy));sx=Math.Sign(sx)*size;sy=Math.Sign(sy)*size;}sx=LimitScale(sx);sy=LimitScale(sy);foreach(var e in selectionPreview){foreach(var p in e.Points){p.X=opposite.X+(p.X-opposite.X)*sx;p.Y=opposite.Y+(p.Y-opposite.Y)*sy;}if(e.Kind=="text")e.FontSize=Math.Clamp(e.FontSize*Math.Sqrt(Math.Abs(sx*sy)),1,1000);}}
                else {var delta=world-start;foreach(var e in selectionPreview)e.Translate(delta.X,delta.Y);}DrawPreview();DrawOverlay();return;
            }DrawPreview();return;
        }
        if(gestureTool=="Lasso"){if(lasso.Count==0||(world-lasso[^1]).Length>2/session.Zoom)lasso.Add(world);DrawPreview();return;}
        if(stroke is null)return;
        if(gestureTool=="Draw"){sample??=new(world.X,world.Y);AppendInk(sample,Stopwatch.GetTimestamp()/(double)Stopwatch.Frequency);DrawOverlay();return;}
        var end=Constrain(Snap(world),stroke.Points[0].Point,gestureTool);stroke.Points=[stroke.Points[0],new(end.X,end.Y)];preview=stroke;DrawPreview();
    }
    private static double LimitScale(double x)=>Math.Sign(x==0?1:x)*Math.Clamp(Math.Abs(x),.02,100);
    private void AppendInk(InkPoint original,double timestamp)
    {
        if(stroke is null)return;lastWorld=original.Point;if(rawSamples.Count>0&&(original.Point-rawSamples[^1].Point).Length<.001&&Math.Abs(original.Pressure-rawSamples[^1].Pressure)<.002)return;
        if(stroke.Points.Count>=100000||rawSamples.Count>=100000){FinishStroke();session.Status("Long stroke saved. Start a new stroke to continue.");return;}
        var dt=Math.Max(.0001,timestamp-lastTimestamp);original.Velocity=rawSamples.Count>0?(original.Point-rawSamples[^1].Point).Length/dt:0;lastTimestamp=timestamp;
        if(held){if((original.Point-holdAnchor).Length<8/session.Zoom)return;held=false;preview=null;using(var dc=ink.RenderOpen())dc.DrawDrawing(activeInk);}
        if((original.Point-holdAnchor).Length>2/session.Zoom){holdAnchor=original.Point;holdTimer.Stop();if(session.AutoCorrect)holdTimer.Start();}
        rawSamples.Add(original.Copy());
        if(original.RawPressure is {} raw){var activation=Math.Clamp(session.ActivationPressure,0,.95);if(stroke.Points.Count==0&&raw<=activation)return;original.Pressure=DrawingMath.CalibratedPressure(raw,activation);}
        var smoothed=filter.Sample(original.Point,timestamp,session.Smoothing,session.Zoom);var point=original.Copy();point.X=smoothed.X;point.Y=smoothed.Y;stroke.Points.Add(point);moved|=(original.Point-(startWorld??original.Point)).Length*session.Zoom>3;
        using(var dc=activeInk.Append()) {
            if(stroke.Pen=="Highlighter"){var saved=stroke.BrushSettings;stroke.BrushSettings=BoardCodec.Clone(saved!);stroke.BrushSettings.Opacity=1;stroke.BrushSettings.MinOpacity=stroke.BrushSettings.MaxOpacity=1;BoardRenderer.DrawStrokeSegment(dc,stroke,BoardRenderer.VisibleColor(stroke.Color,session.Board),stroke.Points.Count-1);stroke.BrushSettings=saved;}
            else BoardRenderer.DrawStrokeSegment(dc,stroke,BoardRenderer.VisibleColor(stroke.Color,session.Board),stroke.Points.Count-1);
        }
    }
    private void CorrectHeldStroke()
    {
        holdTimer.Stop();if(!down||stroke is null||gestureTool!="Draw"||!session.AutoCorrect||held)return;var candidate=DrawingMath.CorrectShape(stroke,session.Zoom);if(candidate.Kind=="stroke")return;held=true;preview=candidate;holdAnchor=lastWorld??candidate.Points[^1].Point;using(ink.RenderOpen()){}DrawPreview();session.Status($"Hold detected • {candidate.Kind} snapped");
    }
    public void FinishStroke()
    {
        if(!down)return;holdTimer.Stop();var e=held?preview:stroke;down=false;
        if(gestureTool=="Select"){
            if(selectionPreview is not null&&moved){session.Checkpoint();foreach(var item in selectionPreview){var at=session.Board.Elements.FindIndex(x=>x.Id==item.Id);if(at>=0)session.Board.Elements[at]=item;}session.NotifyChanged();}
            else if(selectionPreview is null&&moved&&startWorld is {} a&&lastWorld is {} b){var box=new Rect(a,b);foreach(var item in session.Board.Elements)if(box.Contains(item.Bounds))session.SelectedIds.Add(item.Id);session.NotifyViewChanged();}
        }else if(gestureTool=="Lasso"){
            if(lasso.Count>=3){foreach(var item in session.Board.Elements){var bounds=item.Bounds;if(!bounds.IsEmpty&&DrawingMath.Corners(bounds).All(p=>DrawingMath.InPolygon(p,lasso)))session.SelectedIds.Add(item.Id);}session.NotifyViewChanged();}
        }else if(gestureTool=="Eraser"){if(eraserChanged){PruneEraseSources();session.NotifyChanged();}}
        else if(e is not null&&e.Points.Count>0){
            if(e.Kind is "line" or "arrow" or "dimension"){
                var first=e.Points[0].Point;var end=Constrain(e.Points[^1].Point,first,e.Kind=="dimension"?"Dimension":"Line");if(session.FixedLineLengthMM>0){var exact=DrawingMath.FixedEndpoint(e.Points[0],new(end.X,end.Y),session.FixedLineLengthMM,session.Board.PointsPerMM,session.Board.ScaleDenominator);if(exact is not null)end=exact.Point;else{ClearGesture();session.Status("Fixed line length could not be applied. Check the scale and length.");return;}}var ending=e.Points[^1].Copy();ending.X=end.X;ending.Y=end.Y;e.Points=[e.Points[0],ending];
            }
            if(gestureTool=="Draw"&&rawSamples.Count>0){e.Extra??=[];e.Extra["windowsOriginalSamples"]=JsonSerializer.SerializeToElement(rawSamples,BoardCodec.Options);e.Extra["windowsSmoothing"]=JsonSerializer.SerializeToElement(session.Smoothing);}
            var snapped=held&&e.Kind=="line";ClearGesture();session.Commit(e);if(snapped)LineStraightened?.Invoke(e);session.Status(session.PenActive?"Drawing saved • tablet samples received":"Drawing saved locally");return;
        }
        ClearGesture();Refresh();
    }
    private void ClearGesture(){down=false;stroke=preview=null;selectionPreview=originalSelection=null;startWorld=lastWorld=null;lasso.Clear();rawSamples.Clear();held=false;eraserGesture=false;holdTimer.Stop();activeInk=new();using(ink.RenderOpen()){}DrawPreview();DrawOverlay();}
    private void Erase(Point p)
    {
        var radius=StrokeEraser.PressureRadius(session.EraserRadius,session.LivePressure,session.Zoom);
        if(lastEraserPoint is {} previous){var distance=(p-previous).Length;if(distance<Math.Max(.1,radius*.08))return;var steps=Math.Min(128,Math.Max(1,(int)Math.Ceiling(distance/Math.Max(1,radius*.65))));for(int i=1;i<=steps;i++)EraseAt(previous+(p-previous)*((double)i/steps),radius);}else EraseAt(p,radius);
        lastEraserPoint=p;if(eraserChanged)Refresh();
    }
    private void EraseAt(Point point,double radius)
    {
        Reindex();var range=new Rect(point.X-radius,point.Y-radius,radius*2,radius*2);
        foreach(var e in scene.Query(range)){var id=e.Id;if(e.Locked||!DrawingMath.Hit(e,point,radius))continue;var order=scene.Order(id);
            IReadOnlyList<DrawingElement> pieces=session.EraserMode=="Partial"&&e.Kind=="stroke"?StrokeEraser.Split(e,point,radius):[];
            if(pieces.Count==1&&ReferenceEquals(pieces[0],e))continue;
            if(!eraserCheckpointTaken){session.Checkpoint();eraserCheckpointTaken=true;}var at=session.Board.Elements.FindIndex(item=>item.Id==id);if(at<0)continue;
            if(pieces.Count>0&&e.Extra?.TryGetValue("windowsOriginalSamples",out var originalSamples)==true){var key="windowsEraseSource-"+e.Id.ToString("D");session.Board.Extra??=[];session.Board.Extra[key]=originalSamples;foreach(var piece in pieces){piece.Extra??=[];piece.Extra.Remove("windowsOriginalSamples");piece.Extra["windowsEraseSourceKey"]=JsonSerializer.SerializeToElement(key);}}
            session.Board.Elements.RemoveAt(at);session.Board.Elements.InsertRange(at,pieces);RemoveIndexed(id);foreach(var piece in pieces)scene.Upsert(piece,order);eraserChanged=true;
        }
    }
    private void RemoveIndexed(Guid id){scene.Remove(id);if(cache.Remove(id,out var entry))cachedSamples-=entry.Samples;}
    private void PruneEraseSources() => BoardCodec.PruneDerivedMetadata(session.Board);
    private DrawingElement? Hit(Point point)=>session.Board.Elements.LastOrDefault(e=>DrawingMath.Hit(e,point,6/session.Zoom));
    private Point Snap(Point p){if(!session.Snap)return p;var s=session.Board.GridSpacing;if(session.Board.Background=="Isometric"){var row=s*Math.Sqrt(3)/2;var y=Math.Round(p.Y/row);var x=Math.Round((p.X-(Math.Abs(y)%2)*s/2)/s)*s+(Math.Abs(y)%2)*s/2;return new(x,y*row);}return new(Math.Round(p.X/s)*s,Math.Round(p.Y/s)*s);}
    private Point Constrain(Point end,Point start,string tool){var v=end-start;var directional=tool is "Line" or "Arrow" or "Dimension";var iso=directional&&session.Snap&&session.Board.Background=="Isometric";if(!Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)&&!iso)return end;if(directional){var step=iso?Math.PI/6:Math.PI/4;var angle=Math.Round(Math.Atan2(v.Y,v.X)/step)*step;return new(start.X+Math.Cos(angle)*v.Length,start.Y+Math.Sin(angle)*v.Length);}var length=Math.Max(Math.Abs(v.X),Math.Abs(v.Y));return new(start.X+(v.X<0?-length:length),start.Y+(v.Y<0?-length:length));}
    private static string Kind(string tool)=>tool switch{"Line"=>"line","Arrow"=>"arrow","Rectangle"=>"rectangle","Circle" or "Ellipse"=>"ellipse","Triangle"=>"triangle","Arc"=>"arc","Dimension"=>"dimension",_=>"stroke"};
    private void StartPan(Point screen){FinishStroke();panning=true;startScreen=screen;panOrigin=session.Offset;Cursor=Cursors.Hand;}
    private void UpdatePan(Point screen){var delta=screen-startScreen;session.Offset=panOrigin+delta;Refresh();session.NotifyViewChanged();}
    protected override void OnTouchDown(TouchEventArgs e){base.OnTouchDown(e);if(session.PenActive){e.Handled=true;return;}FinishStroke();touches[e.TouchDevice.Id]=e.GetTouchPoint(this).Position;e.TouchDevice.Capture(this);ResetTouchGesture();e.Handled=true;}
    protected override void OnTouchMove(TouchEventArgs e){base.OnTouchMove(e);if(session.PenActive){e.Handled=true;return;}if(!touches.ContainsKey(e.TouchDevice.Id))return;touches[e.TouchDevice.Id]=e.GetTouchPoint(this).Position;var pts=touches.Values.ToArray();var center=new Point(pts.Average(p=>p.X),pts.Average(p=>p.Y));if(pts.Length>=2){var distance=(pts[0]-pts[1]).Length;var factor=touchDistance>.1?Math.Clamp(distance/touchDistance,.5,2):1;var world=WorldPoint(touchCenter);session.Zoom=Math.Clamp(session.Zoom*factor,.02,40);session.Offset=new(center.X-world.X*session.Zoom,center.Y-world.Y*session.Zoom);touchDistance=distance;}else session.Offset+=center-touchCenter;touchCenter=center;Refresh();session.NotifyViewChanged();e.Handled=true;}
    protected override void OnTouchUp(TouchEventArgs e){base.OnTouchUp(e);touches.Remove(e.TouchDevice.Id);e.TouchDevice.Capture(null);ResetTouchGesture();e.Handled=true;}
    private void ResetTouchGesture(){var pts=touches.Values.ToArray();if(pts.Length==0)return;touchCenter=new(pts.Average(p=>p.X),pts.Average(p=>p.Y));touchDistance=pts.Length>=2?(pts[0]-pts[1]).Length:0;}
    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);if(e.Key==Key.Space){spaceHeld=true;Cursor=Cursors.Hand;e.Handled=true;return;}if(e.Key==Key.Escape){ClearGesture();session.SelectedIds.Clear();Refresh();e.Handled=true;return;}
        if(Keyboard.Modifiers.HasFlag(ModifierKeys.Control)){
            switch(e.Key){case Key.Z:FinishStroke();if(Keyboard.Modifiers.HasFlag(ModifierKeys.Shift))session.Redo();else session.Undo();break;case Key.Y:FinishStroke();session.Redo();break;case Key.A:session.SelectAll();break;case Key.D:FinishStroke();session.DuplicateSelection();break;case Key.V:FinishStroke();Paste();break;case Key.OemPlus:case Key.Add:ZoomAt(new(ActualWidth/2,ActualHeight/2),1.2);break;case Key.OemMinus:case Key.Subtract:ZoomAt(new(ActualWidth/2,ActualHeight/2),1/1.2);break;case Key.D0:FitBoard();break;default:return;}e.Handled=true;return;
        }
        if(e.Key is Key.Delete or Key.Back){FinishStroke();session.DeleteSelection();e.Handled=true;return;}
        if((e.Key is Key.Left or Key.Right or Key.Up or Key.Down)&&session.SelectedIds.Count>0){var step=Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)?10d:1d;var dx=e.Key==Key.Left?-step:e.Key==Key.Right?step:0;var dy=e.Key==Key.Up?-step:e.Key==Key.Down?step:0;session.Checkpoint();foreach(var item in session.Board.Elements.Where(x=>session.SelectedIds.Contains(x.Id)&&!x.Locked))item.Translate(dx,dy);session.NotifyChanged();e.Handled=true;return;}
        var tool=e.Key switch{Key.V=>"Select",Key.L=>"Line",Key.B=>"Draw",Key.E=>"Eraser",Key.T=>"Text",_=>null};if(tool is not null){FinishStroke();session.Tool=tool;session.NotifyViewChanged();e.Handled=true;}
    }
    protected override void OnKeyUp(KeyEventArgs e){base.OnKeyUp(e);if(e.Key==Key.Space){spaceHeld=false;Cursor=Cursors.Arrow;e.Handled=true;}}
    private void EditText(Point world,DrawingElement? existing=null)
    {
        if(existing?.Locked==true)return;var screen=ScreenPoint(world);var box=new TextBox{Text=existing?.Text??"",FontSize=Math.Clamp((existing?.FontSize??24)*session.Zoom,12,48),MinWidth=230,MinHeight=80,MaxWidth=700,AcceptsReturn=true,TextWrapping=TextWrapping.Wrap,Padding=new(9),BorderThickness=new(2),BorderBrush=InkColor.Blue.Brush()};var popup=new Popup{Child=box,PlacementTarget=this,Placement=PlacementMode.Relative,HorizontalOffset=Math.Clamp(screen.X,0,Math.Max(0,ActualWidth-240)),VerticalOffset=Math.Clamp(screen.Y,0,Math.Max(0,ActualHeight-100)),StaysOpen=false,IsOpen=true};var completed=false;
        void Commit(){if(completed)return;completed=true;popup.IsOpen=false;if(string.IsNullOrWhiteSpace(box.Text))return;if(existing is null)session.AddText(box.Text,world.X,world.Y);else{session.Checkpoint();existing.Text=box.Text;session.NotifyChanged();}Focus();}
        popup.Closed+=(_,_)=>Commit();box.KeyDown+=(_,e)=>{if(e.Key==Key.Escape){completed=true;popup.IsOpen=false;Focus();e.Handled=true;}else if(e.Key==Key.Enter&&Keyboard.Modifiers.HasFlag(ModifierKeys.Control)){Commit();e.Handled=true;}};box.TextChanged+=(_,_)=>{box.FlowDirection=box.Text.Any(c=>c is >= '\u0590' and <= '\u08FF')?FlowDirection.RightToLeft:FlowDirection.LeftToRight;};box.Focus();box.SelectAll();
    }
    private void ShowContext(Point screen){var menu=new ContextMenu();void Add(string text,Action action){var item=new MenuItem{Header=text};item.Click+=(_,_)=>action();menu.Items.Add(item);}Add("Undo",()=>session.Undo());Add("Redo",()=>session.Redo());Add("Select all",()=>session.SelectAll());Add("Copy",()=>BoardClipboard.Copy(session));Add("Cut",()=>BoardClipboard.Cut(session));Add("Duplicate selection",()=>session.DuplicateSelection());Add("Delete selection",()=>session.DeleteSelection());Add("Paste",Paste);Add("Fit drawing",FitBoard);menu.PlacementTarget=this;menu.IsOpen=true;}
    public void Paste() => BoardClipboard.Paste(session,this);
    public void AddImage(byte[] data,Point world)
    {
        if(data.LongLength>BoardCodec.MaximumBytes){session.Status("Image exceeds the 256 MB limit.");return;}var image=BoardRenderer.DecodeImage(data);var width=Math.Min(700,image.PixelWidth);var height=width*image.PixelHeight/Math.Max(1d,image.PixelWidth);session.Commit(new(){Kind="image",ImageData=data,Points=[new(world.X,world.Y),new(world.X+width,world.Y+height)]});
    }
    protected override void OnDragOver(DragEventArgs e){base.OnDragOver(e);e.Effects=e.Data.GetDataPresent(DataFormats.FileDrop)||e.Data.GetDataPresent("EngBoardSymbol")?DragDropEffects.Copy:DragDropEffects.None;e.Handled=true;}
    protected override void OnDrop(DragEventArgs e)
    {
        base.OnDrop(e);FinishStroke();try {
            var at=Snap(WorldPoint(e.GetPosition(this)));
            if(e.Data.GetData("EngBoardSymbol") is string symbolId) {
                var id=symbolId.StartsWith("catalog:",StringComparison.Ordinal)?symbolId[8..]:symbolId;
                if(id.Length is >0 and <160&&id.All(c=>char.IsAsciiLetterOrDigit(c)||c is '_' or '-' or '.')&&!id.Contains("..",StringComparison.Ordinal)&&File.Exists(Path.Combine(AppContext.BaseDirectory,"Resources","Symbols",id+".png"))) {
                    session.PendingSymbolId=null;var item=new DrawingElement{Kind="symbol",Text="catalog:"+id,Points=[new(at.X,at.Y),new(at.X+240,at.Y+180)],Color=session.Color,Width=session.Settings.MaxWidth};session.Commit(item);session.SelectedIds=[item.Id];session.NotifyViewChanged();StartSymbolAnimation(item);session.Status("Symbol placed. Use Select to move and resize it.");
                } else session.Status("This symbol is not in the installed symbol catalogue.");
            } else if(e.Data.GetData(DataFormats.FileDrop) is string[] files) {
                foreach(var file in files) {
                    var extension=Path.GetExtension(file).ToLowerInvariant();
                    if(extension is ".engboard" or ".pdf") {if(FileDropRequested is not null)FileDropRequested(file);else session.Status("Use File → Open to import this document.");}
                    else if(new[]{".png",".jpg",".jpeg",".bmp",".gif",".tif",".tiff"}.Contains(extension)){var info=new FileInfo(file);if(info.Length>BoardCodec.MaximumBytes)throw new InvalidDataException("Image exceeds the 256 MB limit.");AddImage(File.ReadAllBytes(file),at);at+=new Vector(24,24);}
                }
            }
        } catch(Exception ex) when(ex is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException or System.Text.Json.JsonException){session.Status(ex.Message);}e.Handled=true;
    }
    private void StartSymbolAnimation(DrawingElement e)
    {
        if(!session.ShowSymbolAnimations)return;var id=e.Text.StartsWith("catalog:")?e.Text[8..]:e.Text;if(id.IndexOfAny(Path.GetInvalidFileNameChars())>=0)return;var path=Path.Combine(AppContext.BaseDirectory,"Resources","Frames",id);if(!Directory.Exists(path))return;animationFrames=Directory.EnumerateFiles(path,"frame*.png").OrderBy(x=>x,StringComparer.Ordinal).Take(32).ToArray();if(animationFrames.Length==0)return;animatedId=e.Id;if(cache.TryGetValue(e.Id,out var cached))cached.Visual.Opacity=0;animationStart=DateTime.UtcNow;animationTimer.Start();AdvanceSymbolAnimation();
    }
    private void AdvanceSymbolAnimation()
    {
        if(animatedId is null)return;var elapsed=(DateTime.UtcNow-animationStart).TotalSeconds;if(elapsed>=1||!session.ShowSymbolAnimations){animationTimer.Stop();animatedId=null;Refresh();return;}var element=session.Board.Elements.FirstOrDefault(x=>x.Id==animatedId);if(element is null||element.Points.Count<2){animationTimer.Stop();animatedId=null;return;}var file=animationFrames[(int)(elapsed*animationFrames.Length)%animationFrames.Length];using(var dc=previewVisual.RenderOpen()){var image=BoardRenderer.DecodeImage(File.ReadAllBytes(file));var r=new Rect(element.Points[0].Point,element.Points[^1].Point);var brush=new ImageBrush(image){Stretch=Stretch.Fill,ViewportUnits=BrushMappingMode.Absolute,Viewport=r};dc.PushOpacityMask(brush);dc.DrawRectangle(BoardRenderer.VisibleColor(element.Color,session.Board).Brush(),null,r);dc.Pop();}
    }
    private sealed class CacheEntry(DrawingVisual visual,long signature,int samples,int lastUsed){public DrawingVisual Visual=visual;public long Signature=signature;public int Samples=samples;public int LastUsed=lastUsed;}
}

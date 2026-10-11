using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Media.Media3D;
using System.Windows.Threading;
using Microsoft.Win32;

namespace KarimEldamatyWindows;

public sealed class Sketch3DWindow : Window
{
    private readonly DrawingSession _session;
    private readonly Guid? _sourceId;
    private readonly Guid _boardId;
    private Sketch3DDocument _document = new();
    private readonly Stack<byte[]> _undo = new();
    private readonly Stack<byte[]> _redo = new();
    private Sketch3DDraft? _draft;
    private readonly Viewport3D _viewport = new();
    private readonly ModelVisual3D _objects = new();
    private readonly ModelVisual3D _activeVisual = new();
    private readonly PerspectiveCamera _camera = new() { FieldOfView = 45, NearPlaneDistance = .1, FarPlaneDistance = 100000 };
    private readonly Dictionary<Model3D, Guid> _objectIds = new();
    private readonly TextBlock _status = WorkbenchUI.Label("Draw on the active plane. Right-drag to orbit, middle-drag to pan, wheel to zoom.");
    private readonly ComboBox _mode = new() { ItemsSource = new[] { "Draw", "Select", "Orbit", "Pan" }, SelectedIndex = 0, Width = 90, Margin = new Thickness(3) };
    private readonly ComboBox _plane = new() { ItemsSource = new[] { "Front · XY", "Top · XZ", "Side · YZ" }, SelectedIndex = 1, Width = 125, Margin = new Thickness(3) };
    private readonly ComboBox _colors = new() { Width = 100, Margin = new Thickness(3) };
    private readonly TextBox _colorHex = WorkbenchUI.Field("#FF2963D9", 110);
    private InkColor _currentColor = InkColor.Blue;
    private bool _colorDirty;
    private bool _settingColor;
    private readonly TextBox _title = WorkbenchUI.Field("3D sketch", 150);
    private readonly TextBox _offset = WorkbenchUI.Field("0", 65);
    private readonly TextBox _grid = WorkbenchUI.Field("10", 65);
    private readonly TextBox _width = WorkbenchUI.Field("2", 65);
    private readonly CheckBox _pressure = new() { Content = "Pen pressure", IsChecked = true, Margin = new Thickness(3, 8, 3, 8) };
    private readonly ListBox _list = new() { MinHeight = 150, MaxHeight = 300 };
    private readonly TextBox[] _position = [WorkbenchUI.Field("0", 65), WorkbenchUI.Field("0", 65), WorkbenchUI.Field("0", 65)];
    private readonly TextBox[] _dimensions = [WorkbenchUI.Field("40", 65), WorkbenchUI.Field("40", 65), WorkbenchUI.Field("40", 65)];
    private Guid? _selected;
    private bool _updating;
    private bool _dragging;
    private string _dragMode = "";
    private Point _last;
    private byte[]? _dragBefore;
    private Sketch3DStroke? _stroke;
    private DateTime _lastLiveRender;
    private DateTime _lastDraftSave;
    private string? _openedPath;
    private byte[]? _openedFingerprint;
    private readonly DispatcherTimer _wheelSave = new() { Interval = TimeSpan.FromMilliseconds(450) };

    public Sketch3DWindow(DrawingSession session)
    {
        _session = session; _boardId = session.Board.Id;
        WorkbenchUI.Window(this, "3D Sketch · SketchGlide", 1220, 800);
        var selected = session.Board.Elements.FirstOrDefault(e => session.SelectedIds.Count == 1 && session.SelectedIds.Contains(e.Id) && e.Sketch3D != null);
        if (selected?.Sketch3D is JsonElement scene)
        {
            try { _document = Sketch3DFile.Decode(System.Text.Encoding.UTF8.GetBytes(scene.GetRawText())); _sourceId = selected.Id; }
            catch (Exception error) { _status.Text = "The board scene was kept untouched: " + error.Message; }
        }
        try
        {
            _draft = new Sketch3DDraft(session.Board.Id, _sourceId, App.TestDataDirectory == null ? null : Path.Combine(App.TestDataDirectory, "3D Drafts"));
            var recovered = _draft.Recover();
            if (recovered != null && !Sketch3DFile.Encode(recovered).AsSpan().SequenceEqual(Sketch3DFile.Encode(_document)))
            {
                _undo.Push(Sketch3DFile.Encode(_document)); _document = recovered;
                _status.Text = "Recovered your previous 3D draft. Undo returns to the board's saved scene.";
            }
        }
        catch (Exception error) { _status.Text = "The existing recovery draft was preserved. Use Save 3D to keep changes. " + error.Message; }
        WorkbenchUI.ThemeList(_list);
        BuildUI(); RenderScene();
        _wheelSave.Tick += (_, _) => { _wheelSave.Stop(); SaveDraft(); };
        Closing += (_, e) =>
        {
            FinishInput(); _wheelSave.Stop();
            try { _draft?.Save(_document); }
            catch (Exception error)
            {
                if (MessageBox.Show(this, error.Message + "\nKeep this window open to save the 3D sketch?", "Draft saving stopped", MessageBoxButton.YesNo, MessageBoxImage.Warning) == MessageBoxResult.Yes) e.Cancel = true;
            }
        };
    }
    private void BuildUI()
    {
        var layout = new DockPanel { Margin = new Thickness(12) };
        var toolbar = new WrapPanel { Margin = new Thickness(3, 3, 3, 8) };
        foreach (var child in new UIElement[] { WorkbenchUI.Button("Open 3D…", Import), WorkbenchUI.Button("Save 3D…", Export), WorkbenchUI.Button("Undo", Undo), WorkbenchUI.Button("Redo", Redo), WorkbenchUI.Button("Fit", Fit), WorkbenchUI.Button("Face plane", FacePlane), WorkbenchUI.Button("Insert on board", Insert), WorkbenchUI.Button("Clear scene", () => Mutate(d => { d.Strokes.Clear(); d.Primitives.Clear(); _selected = null; })) }) toolbar.Children.Add(child);
        DockPanel.SetDock(toolbar, Dock.Top); layout.Children.Add(toolbar);
        DockPanel.SetDock(_status, Dock.Bottom); layout.Children.Add(_status);
        var sidebar = new StackPanel { Width = 276 };
        sidebar.Children.Add(WorkbenchUI.Label("Drawing plane", 18));
        sidebar.Children.Add(WorkbenchUI.Row(_plane, _mode));
        sidebar.Children.Add(WorkbenchUI.Row(WorkbenchUI.Label("Offset mm"), _offset));
        sidebar.Children.Add(WorkbenchUI.Row(WorkbenchUI.Label("Grid mm"), _grid));
        sidebar.Children.Add(WorkbenchUI.Row(WorkbenchUI.Label("Title"), _title));
        sidebar.Children.Add(WorkbenchUI.Button("Apply title, plane and grid", ApplyPlane));
        var palette = new[] { ("Blue", InkColor.Blue), ("Teal", InkColor.Teal), ("Graphite", InkColor.Graphite), ("Red", InkColor.Red), ("Amber", InkColor.Amber), ("Violet", InkColor.Violet) };
        foreach (var (name, color) in palette) _colors.Items.Add(new ComboBoxItem { Content = name, Tag = color, Foreground = color.Brush() });
        _colors.SelectedIndex = 0;
        _colors.SelectionChanged += (_, _) => { if ((_colors.SelectedItem as ComboBoxItem)?.Tag is InkColor c) SetColor(c); };
        _colorHex.TextChanged += (_, _) => { if (!_settingColor) _colorDirty = true; };
        sidebar.Children.Add(WorkbenchUI.Row(WorkbenchUI.Label("Colour"), _colors));
        sidebar.Children.Add(WorkbenchUI.Row(WorkbenchUI.Label("Hex / alpha"), _colorHex));
        sidebar.Children.Add(WorkbenchUI.Row(WorkbenchUI.Label("Stroke mm"), _width)); sidebar.Children.Add(_pressure);
        sidebar.Children.Add(WorkbenchUI.Row(WorkbenchUI.Button("Box", () => AddPrimitive("Box")), WorkbenchUI.Button("Cylinder", () => AddPrimitive("Cylinder")), WorkbenchUI.Button("Sphere", () => AddPrimitive("Sphere"))));
        sidebar.Children.Add(WorkbenchUI.Label("Objects · select to edit", 18)); sidebar.Children.Add(_list);
        sidebar.Children.Add(WorkbenchUI.Label("Position X / Y / Z · mm")); sidebar.Children.Add(WorkbenchUI.Row(_position));
        sidebar.Children.Add(WorkbenchUI.Label("Size X / Y / Z · mm")); sidebar.Children.Add(WorkbenchUI.Row(_dimensions));
        sidebar.Children.Add(WorkbenchUI.Label("Cylinder: X diameter, Y height. Sphere: X diameter."));
        sidebar.Children.Add(WorkbenchUI.Row(WorkbenchUI.Button("Apply object edits", ApplySelection), WorkbenchUI.Button("Delete", DeleteSelection)));
        var sideScroll = new ScrollViewer { Content = sidebar, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        var sideCard = WorkbenchUI.Card(sideScroll); DockPanel.SetDock(sideCard, Dock.Right); layout.Children.Add(sideCard);
        _viewport.Camera = _camera; _viewport.ClipToBounds = true;
        _viewport.Children.Add(_objects); _viewport.Children.Add(_activeVisual);
        var viewportBorder = new Border { Child = _viewport, Background = Brushes.WhiteSmoke, CornerRadius = new CornerRadius(12), ClipToBounds = true, Margin = new Thickness(8), Focusable = true };
        viewportBorder.MouseDown += MouseDownViewport; viewportBorder.MouseMove += MouseMoveViewport; viewportBorder.MouseUp += MouseUpViewport;
        viewportBorder.MouseWheel += (_, e) => { _document.Camera.Distance = Math.Clamp(_document.Camera.Distance * Math.Exp(-e.Delta / 120d * .13), 20, 60000); ApplyCamera(); _wheelSave.Stop(); _wheelSave.Start(); e.Handled = true; };
        viewportBorder.StylusDown += StylusDownViewport; viewportBorder.StylusMove += StylusMoveViewport; viewportBorder.StylusUp += StylusUpViewport;
        viewportBorder.LostMouseCapture += (_, _) => { if (_dragging) FinishInput(); };
        viewportBorder.LostStylusCapture += (_, _) => { if (_dragging) FinishInput(); };
        layout.Children.Add(viewportBorder); Content = layout;
        _list.SelectionChanged += (_, _) =>
        {
            if (_updating) return;
            _selected = (_list.SelectedItem as ListBoxItem)?.Tag as Guid?; SyncSelection(); RenderObjects();
        };
        PreviewKeyDown += (_, e) =>
        {
            if (Keyboard.Modifiers == ModifierKeys.Control && e.Key == Key.Z) { Undo(); e.Handled = true; }
            if (Keyboard.Modifiers == ModifierKeys.Control && e.Key == Key.Y) { Redo(); e.Handled = true; }
            if (e.Key == Key.Escape) { FinishInput(); Mouse.Capture(null); Stylus.Capture(null); e.Handled = true; }
            if (e.Key == Key.Delete && Keyboard.FocusedElement is not TextBox) { DeleteSelection(); e.Handled = true; }
        };
        SyncUI();
    }
    private InkColor Color
    {
        get
        {
            if (!_colorDirty) return _currentColor;
            var text = _colorHex.Text.Trim().TrimStart('#');
            if (text.Length is not (6 or 8) || !uint.TryParse(text, System.Globalization.NumberStyles.HexNumber, System.Globalization.CultureInfo.InvariantCulture, out var value)) throw new FormatException("Use a colour such as #2963D9 or #FF2963D9 (alpha, red, green, blue).");
            return new InkColor(((value >> 16) & 255) / 255d, ((value >> 8) & 255) / 255d, (value & 255) / 255d, text.Length == 8 ? ((value >> 24) & 255) / 255d : 1);
        }
    }
    private void SetColor(InkColor color)
    {
        _currentColor = color; _settingColor = true;
        _colorHex.Text = $"#{(int)Math.Round(color.A * 255):X2}{(int)Math.Round(color.R * 255):X2}{(int)Math.Round(color.G * 255):X2}{(int)Math.Round(color.B * 255):X2}";
        _settingColor = false; _colorDirty = false;
    }
    private Point3D PlanePoint(double u, double v) => _document.Plane switch { "XY" => new(u, v, _document.PlaneOffset), "YZ" => new(_document.PlaneOffset, u, v), _ => new(u, _document.PlaneOffset, v) };
    private Vector3D PlaneNormal => _document.Plane switch { "XY" => new(0, 0, 1), "YZ" => new(1, 0, 0), _ => new(0, 1, 0) };
    private void SyncUI()
    {
        _updating = true; _title.Text = _document.Title; _offset.Text = WorkbenchUI.Format(_document.PlaneOffset); _grid.Text = WorkbenchUI.Format(_document.GridSpacing);
        _plane.SelectedIndex = _document.Plane switch { "XY" => 0, "YZ" => 2, _ => 1 };
        _list.Items.Clear();
        foreach (var p in _document.Primitives) _list.Items.Add(new ListBoxItem { Content = p.Kind + " · " + p.Id.ToString()[..6], Tag = p.Id });
        foreach (var s in _document.Strokes) _list.Items.Add(new ListBoxItem { Content = $"Stroke · {s.Points.Count} points", Tag = s.Id });
        foreach (ListBoxItem item in _list.Items) if ((Guid)item.Tag == _selected) _list.SelectedItem = item;
        _updating = false; SyncSelection();
    }
    private void SyncSelection()
    {
        var primitive = _document.Primitives.FirstOrDefault(p => p.Id == _selected);
        var stroke = _document.Strokes.FirstOrDefault(p => p.Id == _selected);
        if (primitive != null)
        {
            SetFields(_position, primitive.Center); SetFields(_dimensions, primitive.Size);
        }
        else if (stroke != null)
        {
            SetFields(_position, Sketch3DPoint.From(StrokeCenter(stroke))); _width.Text = WorkbenchUI.Format(stroke.Width);
        }
        foreach (var field in _position) field.IsEnabled = primitive != null || stroke != null;
        foreach (var field in _dimensions) field.IsEnabled = primitive != null;
        var color = primitive?.Color ?? stroke?.Color;
        if (color != null)
        {
            var index = 0; var closest = double.MaxValue;
            for (var i = 0; i < _colors.Items.Count; i++)
            {
                var c = (InkColor)((ComboBoxItem)_colors.Items[i]).Tag;
                var distance = Math.Pow(c.R - color.R, 2) + Math.Pow(c.G - color.G, 2) + Math.Pow(c.B - color.B, 2);
                if (distance < closest) { closest = distance; index = i; }
            }
            _colors.SelectedIndex = index; SetColor(color);
        }
    }
    private static void SetFields(TextBox[] fields, Sketch3DPoint value) { fields[0].Text = WorkbenchUI.Format(value.X); fields[1].Text = WorkbenchUI.Format(value.Y); fields[2].Text = WorkbenchUI.Format(value.Z); }
    private static Point3D StrokeCenter(Sketch3DStroke stroke) => new((stroke.Points.Min(p => p.X) + stroke.Points.Max(p => p.X)) / 2, (stroke.Points.Min(p => p.Y) + stroke.Points.Max(p => p.Y)) / 2, (stroke.Points.Min(p => p.Z) + stroke.Points.Max(p => p.Z)) / 2);
    private void Mutate(Action<Sketch3DDocument> mutation)
    {
        FinishInput();
        try
        {
            var next = Sketch3DFile.Copy(_document); mutation(next); var data = Sketch3DFile.Encode(next);
            var before = Sketch3DFile.Encode(_document); if (data.AsSpan().SequenceEqual(before)) return;
            PushUndo(before); _document = next; _redo.Clear(); SaveDraft(); SyncUI(); RenderScene();
        }
        catch (Exception error) { WorkbenchUI.Error(this, error); }
    }
    private void PushUndo(byte[] snapshot)
    {
        _undo.Push(snapshot);
        if (_undo.Count > 30) { var kept = _undo.Take(30).Reverse().ToArray(); _undo.Clear(); foreach (var item in kept) _undo.Push(item); }
    }
    private void SaveDraft()
    {
        try
        {
            var document = _document;
            if (_stroke != null) { document = Sketch3DFile.Copy(_document); document.Strokes.Add(_stroke); }
            _draft?.Save(document); _lastDraftSave = DateTime.UtcNow;
        }
        catch (Exception error) { _status.Text = "Draft saving stopped. Save 3D keeps your changes. " + error.Message; }
    }
    private void ApplyPlane()
    {
        try
        {
            var offset = WorkbenchUI.Number(_offset, "Plane offset", -10000, 10000); var grid = WorkbenchUI.Number(_grid, "Grid spacing", 1, 1000);
            var plane = _plane.SelectedIndex switch { 0 => "XY", 2 => "YZ", _ => "XZ" };
            Mutate(d => { d.Plane = plane; d.PlaneOffset = offset; d.GridSpacing = grid; d.Title = _title.Text; });
        }
        catch (Exception error) { WorkbenchUI.Error(this, error); }
    }
    private void AddPrimitive(string kind)
    {
        try
        {
            var item = new Sketch3DPrimitive { Kind = kind, Center = Sketch3DPoint.From(PlanePoint(0, 20)), Color = Color };
            Mutate(d => { d.Primitives.Add(item); _selected = item.Id; });
        }
        catch (Exception error) { WorkbenchUI.Error(this, error); }
    }
    private void ApplySelection()
    {
        if (_selected == null) { _status.Text = "Select an object first."; return; }
        try
        {
            var position = new Sketch3DPoint(WorkbenchUI.Number(_position[0], "X position", -10000, 10000), WorkbenchUI.Number(_position[1], "Y position", -10000, 10000), WorkbenchUI.Number(_position[2], "Z position", -10000, 10000));
            var width = WorkbenchUI.Number(_width, "Stroke width", .2, 10);
            Sketch3DPoint? size = _dimensions[0].IsEnabled ? new(WorkbenchUI.Number(_dimensions[0], "X size", 1, 2000), WorkbenchUI.Number(_dimensions[1], "Y size", 1, 2000), WorkbenchUI.Number(_dimensions[2], "Z size", 1, 2000)) : null;
            Mutate(d =>
            {
                var p = d.Primitives.FirstOrDefault(p => p.Id == _selected);
                if (p != null) { p.Center = position; p.Color = Color; if (size != null) p.Size = size; }
                var s = d.Strokes.FirstOrDefault(p => p.Id == _selected);
                if (s != null) { var delta = position.Point - StrokeCenter(s); foreach (var point in s.Points) { point.X += delta.X; point.Y += delta.Y; point.Z += delta.Z; } s.Color = Color; s.Width = width; }
            });
        }
        catch (Exception error) { WorkbenchUI.Error(this, error); }
    }
    private void DeleteSelection() { if (_selected != null) Mutate(d => { d.Primitives.RemoveAll(p => p.Id == _selected); d.Strokes.RemoveAll(p => p.Id == _selected); _selected = null; }); }
    private void Undo() { FinishInput(); if (_undo.TryPop(out var data)) { _redo.Push(Sketch3DFile.Encode(_document)); _document = Sketch3DFile.Decode(data); _selected = null; SaveDraft(); SyncUI(); RenderScene(); } }
    private void Redo() { FinishInput(); if (_redo.TryPop(out var data)) { PushUndo(Sketch3DFile.Encode(_document)); _document = Sketch3DFile.Decode(data); _selected = null; SaveDraft(); SyncUI(); RenderScene(); } }
    private void FacePlane() => Mutate(d => { d.Camera.Yaw = d.Plane == "YZ" ? Math.PI / 2 : 0; d.Camera.Pitch = d.Plane == "XZ" ? 1.49 : 0; d.Camera.Target = Sketch3DPoint.From(PlanePoint(0, 0)); });
    private void Fit()
    {
        Mutate(d =>
        {
            var points = d.Strokes.SelectMany(s => s.Points).Select(p => p.Point).ToList();
            foreach (var p in d.Primitives) { var half = new Vector3D(p.Size.X / 2, p.Size.Y / 2, p.Size.Z / 2); points.Add(p.Center.Point - half); points.Add(p.Center.Point + half); }
            if (points.Count == 0) { d.Camera = new(); return; }
            var min = new Point3D(points.Min(p => p.X), points.Min(p => p.Y), points.Min(p => p.Z)); var max = new Point3D(points.Max(p => p.X), points.Max(p => p.Y), points.Max(p => p.Z));
            d.Camera.Target = Sketch3DPoint.From(min + (max - min) / 2); var radius = Math.Max(35, (max - min).Length / 2 + 10);
            d.Camera.Distance = Math.Clamp(radius / Math.Sin(Math.PI / 8) * 1.2 / Math.Min(1, Math.Max(.25, _viewport.ActualWidth / Math.Max(1, _viewport.ActualHeight))), 120, 60000);
        });
    }
    private void RenderScene() { RenderObjects(); ApplyCamera(); }
    private void RenderObjects()
    {
        var group = new Model3DGroup(); _objectIds.Clear();
        group.Children.Add(new AmbientLight(System.Windows.Media.Color.FromRgb(155, 155, 155)));
        group.Children.Add(new DirectionalLight(Colors.White, new Vector3D(-.4, -1, -.6)));
        var spacing = _document.GridSpacing; var extent = Math.Min(10000, spacing * 10);
        for (var i = -10; i <= 10; i++)
        {
            AddLine(group, PlanePoint(i * spacing, -extent), PlanePoint(i * spacing, extent), new InkColor(.68, .73, .79, .7), .16);
            AddLine(group, PlanePoint(-extent, i * spacing), PlanePoint(extent, i * spacing), new InkColor(.68, .73, .79, .7), .16);
        }
        AddLine(group, new Point3D(), new Point3D(60, 0, 0), InkColor.Red, .6);
        AddLine(group, new Point3D(), new Point3D(0, 60, 0), InkColor.Teal, .6);
        AddLine(group, new Point3D(), new Point3D(0, 0, 60), InkColor.Blue, .6);
        foreach (var p in _document.Primitives) { var model = Sketch3DGeometry.Model(Sketch3DGeometry.Primitive(p), p.Color, p.Id == _selected); group.Children.Add(model); _objectIds[model] = p.Id; }
        foreach (var s in _document.Strokes) { var model = Sketch3DGeometry.Model(Sketch3DGeometry.Tube(s.Points, s.Width), s.Color, s.Id == _selected); group.Children.Add(model); _objectIds[model] = s.Id; }
        _objects.Content = group;
        RenderActive();
    }
    private static void AddLine(Model3DGroup group, Point3D a, Point3D b, InkColor color, double width) => group.Children.Add(Sketch3DGeometry.Model(Sketch3DGeometry.Tube([Sketch3DPoint.From(a), Sketch3DPoint.From(b)], width), color));
    private void RenderActive() { _activeVisual.Content = _stroke == null ? null : Sketch3DGeometry.Model(Sketch3DGeometry.Tube(_stroke.Points, _stroke.Width), _stroke.Color); _lastLiveRender = DateTime.UtcNow; }
    private void ApplyCamera()
    {
        var c = _document.Camera; var direction = new Vector3D(Math.Sin(c.Yaw) * Math.Cos(c.Pitch), Math.Sin(c.Pitch), Math.Cos(c.Yaw) * Math.Cos(c.Pitch));
        _camera.Position = c.Target.Point + direction * c.Distance; _camera.LookDirection = -direction * c.Distance;
        _camera.UpDirection = new Vector3D(0, 1, 0);
    }
    private Sketch3DPoint? Project(Point point, double pressure)
    {
        var look = _camera.LookDirection; look.Normalize(); var right = Vector3D.CrossProduct(look, _camera.UpDirection); right.Normalize(); var up = Vector3D.CrossProduct(right, look); up.Normalize();
        var width = Math.Max(1, _viewport.ActualWidth); var height = Math.Max(1, _viewport.ActualHeight); var tangent = Math.Tan(_camera.FieldOfView * Math.PI / 360);
        var ray = look + right * ((point.X / width * 2 - 1) * tangent) + up * ((1 - point.Y / height * 2) * tangent * height / width); ray.Normalize();
        var denominator = Vector3D.DotProduct(ray, PlaneNormal); if (Math.Abs(denominator) < 1e-8) return null;
        var distance = (_document.PlaneOffset - Vector3D.DotProduct((Vector3D)_camera.Position, PlaneNormal)) / denominator;
        if (!double.IsFinite(distance) || distance < .1 || distance > 100000) return null;
        var hit = _camera.Position + ray * distance;
        if (Math.Abs(hit.X) > 10000 || Math.Abs(hit.Y) > 10000 || Math.Abs(hit.Z) > 10000) return null;
        return Sketch3DPoint.From(hit, _pressure.IsChecked == true ? Math.Clamp(pressure, 0, 1) : 1);
    }
    private void MouseDownViewport(object sender, MouseButtonEventArgs e)
    {
        if (e.StylusDevice != null) return;
        _dragMode = e.ChangedButton == MouseButton.Right ? "Orbit" : e.ChangedButton == MouseButton.Middle ? "Pan" : _mode.SelectedItem as string ?? "Draw";
        if (_dragMode == "Select") { SelectAt(e.GetPosition(_viewport)); e.Handled = true; return; }
        StartInput(e.GetPosition(_viewport), 1); if (_dragging) ((UIElement)sender).CaptureMouse(); e.Handled = true;
    }
    private void MouseMoveViewport(object sender, MouseEventArgs e) { if (e.StylusDevice == null && _dragging) MoveInput(e.GetPosition(_viewport), 1); }
    private void MouseUpViewport(object sender, MouseButtonEventArgs e) { if (e.StylusDevice != null) return; FinishInput(); ((UIElement)sender).ReleaseMouseCapture(); e.Handled = true; }
    private void StylusDownViewport(object sender, StylusDownEventArgs e)
    {
        if (e.StylusDevice.TabletDevice.Type == TabletDeviceType.Touch) { e.Handled = true; return; }
        _dragMode = _mode.SelectedItem as string ?? "Draw"; var points = e.GetStylusPoints(_viewport);
        if (_dragMode == "Select") SelectAt(e.GetPosition(_viewport));
        else { StartInput(e.GetPosition(_viewport), points.Count > 0 ? points[^1].PressureFactor : 1); if (_dragging) ((UIElement)sender).CaptureStylus(); }
        e.Handled = true;
    }
    private void StylusMoveViewport(object sender, StylusEventArgs e) { if (e.StylusDevice.TabletDevice.Type == TabletDeviceType.Touch) { e.Handled = true; return; } if (_dragging) foreach (var p in e.GetStylusPoints(_viewport)) MoveInput(new Point(p.X, p.Y), p.PressureFactor); e.Handled = true; }
    private void StylusUpViewport(object sender, StylusEventArgs e) { if (e.StylusDevice.TabletDevice.Type == TabletDeviceType.Touch) { e.Handled = true; return; } FinishInput(); ((UIElement)sender).ReleaseStylusCapture(); e.Handled = true; }
    private void SelectAt(Point point)
    {
        Guid? id = null;
        VisualTreeHelper.HitTest(_viewport, null, result =>
        {
            if (result is RayMeshGeometry3DHitTestResult hit && _objectIds.TryGetValue(hit.ModelHit, out var found)) { id = found; return HitTestResultBehavior.Stop; }
            return HitTestResultBehavior.Continue;
        }, new PointHitTestParameters(point));
        _selected = id; SyncUI(); RenderObjects();
    }
    private void StartInput(Point point, double pressure)
    {
        FinishInput(); _last = point; _dragBefore = Sketch3DFile.Encode(_document);
        if (_dragMode == "Draw")
        {
            try
            {
                if (_document.Strokes.Count >= 200 || _document.Strokes.Sum(s => s.Points.Count) >= 40000) throw new InvalidOperationException("The scene limit was reached. Remove an object or open a new scene.");
                var hit = Project(point, pressure); if (hit == null) { _status.Text = "Face the drawing plane to begin a stroke."; return; }
                _stroke = new Sketch3DStroke { Color = Color, Width = WorkbenchUI.Number(_width, "Stroke width", .2, 10), Points = [hit] }; _selected = null; RenderActive(); SaveDraft();
            }
            catch (Exception error) { WorkbenchUI.Error(this, error); return; }
        }
        _dragging = true;
    }
    private void MoveInput(Point point, double pressure)
    {
        var delta = point - _last; _last = point;
        if (_dragMode == "Draw" && _stroke != null)
        {
            var hit = Project(point, pressure);
            if (hit != null && _stroke.Points.Count < 4096 && _document.Strokes.Sum(s => s.Points.Count) + _stroke.Points.Count < 40000 && (hit.Point - _stroke.Points[^1].Point).Length >= .25) _stroke.Points.Add(hit);
            if ((DateTime.UtcNow - _lastLiveRender).TotalMilliseconds > 32) RenderActive();
            if ((DateTime.UtcNow - _lastDraftSave).TotalMilliseconds > 750) SaveDraft();
        }
        else if (_dragMode == "Orbit") { _document.Camera.Yaw = Math.Clamp(_document.Camera.Yaw - delta.X * .008, -1000, 1000); _document.Camera.Pitch = Math.Clamp(_document.Camera.Pitch + delta.Y * .008, -1.49, 1.49); ApplyCamera(); }
        else if (_dragMode == "Pan")
        {
            var look = _camera.LookDirection; look.Normalize(); var right = Vector3D.CrossProduct(look, _camera.UpDirection); right.Normalize(); var up = Vector3D.CrossProduct(right, look); up.Normalize();
            var target = _document.Camera.Target.Point + (-right * delta.X + up * delta.Y) * (_document.Camera.Distance * .8 / Math.Max(1, _viewport.ActualWidth));
            _document.Camera.Target = new(Math.Clamp(target.X, -10000, 10000), Math.Clamp(target.Y, -10000, 10000), Math.Clamp(target.Z, -10000, 10000)); ApplyCamera();
        }
    }
    private void FinishInput()
    {
        if (!_dragging && _stroke == null) return;
        _dragging = false;
        if (_stroke != null) { _document.Strokes.Add(_stroke); _stroke = null; }
        if (_dragBefore != null && !Sketch3DFile.Encode(_document).AsSpan().SequenceEqual(_dragBefore)) { PushUndo(_dragBefore); _redo.Clear(); }
        _dragBefore = null; SaveDraft(); SyncUI(); RenderScene();
    }
    private void Import()
    {
        FinishInput(); var dialog = new OpenFileDialog { Filter = "Editable 3D sketch (*.karim3d)|*.karim3d|JSON scene (*.json)|*.json", CheckFileExists = true };
        if (dialog.ShowDialog(this) != true) return;
        try { var imported = Sketch3DFile.Read(dialog.FileName); Mutate(d => { d.Version = imported.Version; d.Title = imported.Title; d.Units = imported.Units; d.Plane = imported.Plane; d.PlaneOffset = imported.PlaneOffset; d.GridSpacing = imported.GridSpacing; d.Strokes = imported.Strokes; d.Primitives = imported.Primitives; d.Camera = imported.Camera; _selected = null; }); _openedPath = dialog.FileName; _openedFingerprint = File.ReadAllBytes(dialog.FileName); _status.Text = "Opened editable 3D scene. Your previous scene remains available in Undo."; }
        catch (Exception error) { WorkbenchUI.Error(this, error); }
    }
    private void Export()
    {
        FinishInput(); var dialog = new SaveFileDialog { Filter = "Editable 3D sketch (*.karim3d)|*.karim3d", DefaultExt = ".karim3d", FileName = "3D sketch.karim3d", OverwritePrompt = true };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            if (string.Equals(dialog.FileName, _openedPath, StringComparison.OrdinalIgnoreCase) && _openedFingerprint != null && (!File.Exists(dialog.FileName) || new FileInfo(dialog.FileName).Length > Sketch3DFile.MaximumBytes || !File.ReadAllBytes(dialog.FileName).AsSpan().SequenceEqual(_openedFingerprint))) throw new IOException("The opened 3D file changed outside this window. Save under a new name to preserve both versions.");
            var bytes = Sketch3DFile.Encode(_document); Sketch3DFile.WriteAtomic(dialog.FileName, bytes); _openedPath = dialog.FileName; _openedFingerprint = bytes; _status.Text = "Saved editable .karim3d scene.";
        }
        catch (Exception error) { WorkbenchUI.Error(this, error); }
    }
    private void Insert()
    {
        FinishInput();
        try
        {
            if (_session.Board.Id != _boardId) throw new InvalidOperationException("The board changed while this 3D window was open. Save the 3D sketch and reopen it from the intended board.");
            if (_document.Primitives.Count + _document.Strokes.Count == 0) throw new InvalidOperationException("Draw a stroke or add a shape first.");
            Sketch3DFile.Validate(_document); _selected = null; RenderScene(); _viewport.UpdateLayout();
            var width = Math.Clamp((int)Math.Ceiling(_viewport.ActualWidth), 1, 4096); var height = Math.Clamp((int)Math.Ceiling(_viewport.ActualHeight), 1, 4096);
            if (width < 100 || height < 100) throw new InvalidOperationException("Open and size the 3D viewport before inserting.");
            var rendered = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32); rendered.Render(_viewport);
            var visual = new DrawingVisual(); using (var context = visual.RenderOpen()) { context.DrawRectangle(Brushes.WhiteSmoke, null, new Rect(0, 0, width, height)); context.DrawImage(rendered, new Rect(0, 0, width, height)); }
            var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32); bitmap.Render(visual);
            var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap)); using var stream = new MemoryStream(); encoder.Save(stream);
            var png = stream.ToArray(); if (png.Length > Sketch3DFile.MaximumBytes) throw new InvalidOperationException("The snapshot exceeds 16 MB. Resize the viewport and try again.");
            var scene = JsonSerializer.SerializeToElement(_document, Sketch3DFile.Options).Clone();
            var source = _session.Board.Elements.FirstOrDefault(e => e.Id == _sourceId && e.Kind == "image" && !e.Locked);
            if (source == null && _session.Board.Elements.Count >= 100000) throw new InvalidOperationException("The board object limit was reached. Save the scene separately and use a new board.");
            _session.Checkpoint();
            if (source != null) { source.ImageData = png; source.Sketch3D = scene; source.Text = _document.Title; _session.SelectedIds.Clear(); _session.SelectedIds.Add(source.Id); }
            else
            {
                var w = Math.Min(640, Math.Max(100, _session.Board.Width * .5)); var h = w * height / width;
                var x = _session.Board.Width / 2 - w / 2; var y = _session.Board.Height / 2 - h / 2;
                var element = new DrawingElement { Kind = "image", ImageData = png, Sketch3D = scene, Text = _document.Title, Points = [new InkPoint(x, y), new InkPoint(x + w, y + h)] };
                _session.Board.Elements.Add(element); _session.SelectedIds.Clear(); _session.SelectedIds.Add(element.Id);
            }
            _session.NotifyChanged(); SaveDraft(); _status.Text = "Saved on the board with its editable 3D scene. Select it and reopen 3D Sketch to edit.";
        }
        catch (Exception error) { WorkbenchUI.Error(this, error); }
    }
}

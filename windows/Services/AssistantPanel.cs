using System.Windows;
using System.Windows.Controls;
namespace KarimEldamatyWindows;

public sealed class AssistantPanel : UserControl
{
    private readonly DrawingSession session;
    private readonly AssistantService service = new();
    private AISettingsConfig settings = AISettingsConfig.Load();
    private readonly TextBox prompt = ServiceUI.Input("", true), answer = ServiceUI.Input("", true);
    private readonly TextBlock route = ServiceUI.Text(""), status = ServiceUI.Text("Ready", 12, true);
    private readonly CheckBox attach = ServiceUI.Check("Attach drawing PNG to this Send");
    private readonly Button send, cancel, insert;
    private CancellationTokenSource? pending;
    public AssistantPanel(DrawingSession session)
    {
        this.session = session; MinWidth = 280;
        var stack = new StackPanel { Margin = new Thickness(16) }; stack.Children.Add(ServiceUI.Text("Engineering assistant", 21));
        stack.Children.Add(ServiceUI.Text("Write a question or ask for a worked explanation. Every request uses the route shown below. Check numbers, units and sources before using an answer.", 12, true));
        stack.Children.Add(route); stack.Children.Add(ServiceUI.Button("AI settings", OpenSettings));
        stack.Children.Add(prompt); prompt.MinHeight = 125; prompt.ToolTip = "Only this prompt and an explicitly attached drawing image are sent.";
        stack.Children.Add(attach); stack.Children.Add(ServiceUI.Text("OpenAI sends your prompt and any checked image to the OpenAI API. Local Ollama sends text to your own computer. Auto uses the configured local model, otherwise OpenAI; it does not switch routes after an error.", 11, true));
        var actions = new WrapPanel(); send = ServiceUI.Button("Send", () => _ = SendAsync()); cancel = ServiceUI.Button("Cancel", () => pending?.Cancel()); cancel.IsEnabled = false; actions.Children.Add(send); actions.Children.Add(cancel); stack.Children.Add(actions);
        stack.Children.Add(status); answer.IsReadOnly = true; answer.MinHeight = 220; stack.Children.Add(answer);
        var output = new WrapPanel(); output.Children.Add(ServiceUI.Button("Copy answer", () => { if (answer.Text.Length > 0) {ServiceUI.TryCopyText(answer.Text,out var message);status.Text=message;} })); insert = ServiceUI.Button("Insert answer as text", Insert); insert.IsEnabled = false; output.Children.Add(insert); stack.Children.Add(output);
        Content = new ScrollViewer { Content = stack, VerticalScrollBarVisibility = ScrollBarVisibility.Auto }; SetResourceReference(BackgroundProperty, "SurfaceBrush"); RefreshRoute();
        Unloaded += (_, _) => pending?.Cancel();
    }
    private void RefreshRoute() { route.Text = settings.RouteDescription; attach.IsEnabled = settings.EffectiveBackend == AIBackend.OpenAI; if (!attach.IsEnabled) attach.IsChecked = false; }
    private void OpenSettings() { var window = new AISettingsWindow(settings) { Owner = Window.GetWindow(this) }; if (window.ShowDialog() == true) { settings = AISettingsConfig.Load(); RefreshRoute(); } }
    private async Task SendAsync()
    {
        if (pending != null) return;
        pending = new CancellationTokenSource(); send.IsEnabled = false; cancel.IsEnabled = true; insert.IsEnabled = false; status.Text = "Sending to " + settings.RouteDescription + "…";
        try { var png = attach.IsChecked == true ? BoardExport.RenderPNG(session.Board) : null; var result = await service.SendAsync(settings, prompt.Text.Trim(), png, pending.Token); answer.Text = result.Text; status.Text = "Answered via " + result.Route; insert.IsEnabled = answer.Text.Length > 0; }
        catch (OperationCanceledException) { status.Text = "Cancelled. Your drawing is unchanged."; }
        catch (Exception ex) { status.Text = ex.Message; }
        finally { pending.Dispose(); pending = null; send.IsEnabled = true; cancel.IsEnabled = false; }
    }
    private void Insert() { if (string.IsNullOrWhiteSpace(answer.Text)) return; session.AddText(answer.Text, 70, 70, 20); status.Text = "Answer inserted. Review it on the drawing; Undo is available."; }
}

public sealed class AISettingsWindow : Window
{
    public AISettingsWindow(AISettingsConfig settings)
    {
        SetResourceReference(StyleProperty, typeof(Window));
        Title = "AI settings"; Width = 530; Height = 620; WindowStartupLocation = WindowStartupLocation.CenterOwner; ResizeMode = ResizeMode.CanResize;
        SetResourceReference(BackgroundProperty, "SurfaceBrush");
        var stack = new StackPanel { Margin = new Thickness(20) }; stack.Children.Add(ServiceUI.Text("Choose where Send goes", 22));
        var backend = new ComboBox { ItemsSource = Enum.GetValues<AIBackend>(), SelectedItem = settings.Backend, Margin = new Thickness(0, 5, 0, 12), Padding = new Thickness(8) }; stack.Children.Add(backend);
        stack.Children.Add(ServiceUI.Text("OpenAI model")); var model = ServiceUI.Input(settings.Model); stack.Children.Add(model);
        stack.Children.Add(ServiceUI.Text("OpenAI API key (encrypted for this Windows user)")); var key = new PasswordBox { Padding = new Thickness(9), Margin = new Thickness(0, 4, 0, 8) }; stack.Children.Add(key);
        var keyStatus = ServiceUI.Text("Leave the field empty to keep the saved key.", 11, true); stack.Children.Add(keyStatus);
        try { if (CredentialStore.Read("openai-api-key") is { Length: > 0 }) keyStatus.Text = "A key is saved. Leave empty to keep it, or use Remove saved key."; } catch (Exception ex) { keyStatus.Text = ex.Message; }
        stack.Children.Add(ServiceUI.Button("Remove saved key", () => { try { CredentialStore.Delete("openai-api-key"); key.Clear(); keyStatus.Text = "Saved API key removed."; } catch (Exception ex) { keyStatus.Text = ex.Message; } }));
        stack.Children.Add(ServiceUI.Text("Local Ollama model")); var local = new ComboBox { IsEditable = true, Text = settings.LocalModel, Margin = new Thickness(0, 4, 0, 8), Padding = new Thickness(8) }; stack.Children.Add(local);
        var status = ServiceUI.Text("Ollama is optional. Install it separately and pull a model. This app only connects to 127.0.0.1:11434.", 12, true); stack.Children.Add(status);
        var refresh = ServiceUI.Button("Refresh installed local models", () => { });
        refresh.Click += async (_, _) => { refresh.IsEnabled = false; try { var models = await new AssistantService().ListLocalModelsAsync(CancellationToken.None); local.ItemsSource = models; status.Text = models.Count == 0 ? "No installed models found. Pull a model in Ollama first." : "Choose an installed model or type its exact name."; } catch { status.Text = "Ollama is not ready on 127.0.0.1:11434. Start it, then refresh."; } finally { refresh.IsEnabled = true; } }; stack.Children.Add(refresh);
        stack.Children.Add(ServiceUI.Text("Nothing is sent to either assistant when this window opens. Send makes the request. An OpenAI API key is separate from a ChatGPT subscription.", 11, true));
        stack.Children.Add(ServiceUI.Button("Save settings", () => { try { var next = new AISettingsConfig { Backend = (AIBackend)(backend.SelectedItem ?? AIBackend.Auto), Model = model.Text.Trim(), LocalModel = local.Text.Trim() }; next.Validate(); if (key.Password.Trim().Length > 0) CredentialStore.Save("openai-api-key", key.Password.Trim()); next.Save(); DialogResult = true; } catch (Exception ex) { status.Text = ex.Message; } }));
        Content = new ScrollViewer { Content = stack, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }
}

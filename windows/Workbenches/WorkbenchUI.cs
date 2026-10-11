using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace KarimEldamatyWindows;

internal static class WorkbenchUI
{
    public static Button Button(string text, Action action)
    {
        var button = new Button { Content = text, Margin = new Thickness(3), Padding = new Thickness(10, 7, 10, 7) };
        button.Click += (_, _) => action();
        return button;
    }
    public static TextBlock Label(string text, double size = 14)
    {
        var label = new TextBlock { Text = text, FontSize = size, Margin = new Thickness(3, 7, 3, 5), TextWrapping = TextWrapping.Wrap };
        label.SetResourceReference(TextBlock.ForegroundProperty, "TextBrush");
        return label;
    }
    public static TextBox Field(string value, double width = 90)
    {
        var box = new TextBox { Text = value, MinWidth = width, Margin = new Thickness(3), Padding = new Thickness(7), VerticalContentAlignment = VerticalAlignment.Center };
        return box;
    }
    public static StackPanel Row(params UIElement[] children)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var child in children) row.Children.Add(child);
        return row;
    }
    public static void ThemeList(ListBox list)
    {
        list.SetResourceReference(Control.ForegroundProperty, "TextBrush");
        list.SetResourceReference(Control.BackgroundProperty, "SurfaceBrush");
        list.SetResourceReference(Control.BorderBrushProperty, "BorderBrush");
        VirtualizingPanel.SetIsVirtualizing(list, true);
        VirtualizingPanel.SetVirtualizationMode(list, VirtualizationMode.Recycling);
        ScrollViewer.SetCanContentScroll(list, true);
    }
    public static Border Card(UIElement child)
    {
        var border = new Border { Child = child, Padding = new Thickness(14), Margin = new Thickness(8), CornerRadius = new CornerRadius(12), BorderThickness = new Thickness(1) };
        border.SetResourceReference(Border.BackgroundProperty, "CardBrush");
        border.SetResourceReference(Border.BorderBrushProperty, "BorderBrush");
        return border;
    }
    public static void Window(Window window, string title, double width, double height)
    {
        window.SetResourceReference(FrameworkElement.StyleProperty, typeof(System.Windows.Window));
        window.Title = title; window.Width = width; window.Height = height;
        window.MinWidth = Math.Min(width, 800); window.MinHeight = Math.Min(height, 580);
        window.WindowStartupLocation = WindowStartupLocation.CenterOwner;
        window.SetResourceReference(System.Windows.Window.BackgroundProperty, "SurfaceBrush");
        window.SetResourceReference(Control.ForegroundProperty, "TextBrush");
    }
    public static double Number(TextBox field, string name, double minimum, double maximum)
    {
        if (!double.TryParse(field.Text, NumberStyles.Float, CultureInfo.InvariantCulture, out var number) || !double.IsFinite(number) || number < minimum || number > maximum)
            throw new FormatException($"{name} must be between {minimum:g} and {maximum:g}.");
        return number;
    }
    public static string Format(double number) => number.ToString("G10", CultureInfo.InvariantCulture);
    public static void Error(Window owner, Exception error) => MessageBox.Show(owner, error.Message, "Please check", MessageBoxButton.OK, MessageBoxImage.Warning);
}

using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Avo.Windows.Controls;

/// <summary>Dark AVO card (Android AvoCard): optional title, optional header content on the right, body content.</summary>
public class AvoCard : HeaderedContentControl
{
    public static readonly DependencyProperty HeaderToolsProperty = DependencyProperty.Register(nameof(HeaderTools), typeof(object), typeof(AvoCard));
    public static readonly DependencyProperty AccentProperty = DependencyProperty.Register(nameof(Accent), typeof(Brush), typeof(AvoCard));
    public object? HeaderTools { get => GetValue(HeaderToolsProperty); set => SetValue(HeaderToolsProperty, value); }
    /// <summary>Optional brush of a thin left accent bar.</summary>
    public Brush? Accent { get => (Brush?)GetValue(AccentProperty); set => SetValue(AccentProperty, value); }
}

/// <summary>Metric tile: label, large value with unit, caption and optional content (e.g. a sparkline).</summary>
public class AvoMetricTile : ContentControl
{
    public static readonly DependencyProperty LabelProperty = DependencyProperty.Register(nameof(Label), typeof(string), typeof(AvoMetricTile), new PropertyMetadata(""));
    public static readonly DependencyProperty ValueProperty = DependencyProperty.Register(nameof(Value), typeof(string), typeof(AvoMetricTile), new PropertyMetadata("—"));
    public static readonly DependencyProperty UnitProperty = DependencyProperty.Register(nameof(Unit), typeof(string), typeof(AvoMetricTile), new PropertyMetadata(""));
    public static readonly DependencyProperty CaptionProperty = DependencyProperty.Register(nameof(Caption), typeof(string), typeof(AvoMetricTile), new PropertyMetadata(""));
    public static readonly DependencyProperty ValueBrushProperty = DependencyProperty.Register(nameof(ValueBrush), typeof(Brush), typeof(AvoMetricTile));
    public static readonly DependencyProperty ValueSizeProperty = DependencyProperty.Register(nameof(ValueSize), typeof(double), typeof(AvoMetricTile), new PropertyMetadata(26.0));
    public string Label { get => (string)GetValue(LabelProperty); set => SetValue(LabelProperty, value); }
    public string Value { get => (string)GetValue(ValueProperty); set => SetValue(ValueProperty, value); }
    public string Unit { get => (string)GetValue(UnitProperty); set => SetValue(UnitProperty, value); }
    public string Caption { get => (string)GetValue(CaptionProperty); set => SetValue(CaptionProperty, value); }
    public Brush? ValueBrush { get => (Brush?)GetValue(ValueBrushProperty); set => SetValue(ValueBrushProperty, value); }
    public double ValueSize { get => (double)GetValue(ValueSizeProperty); set => SetValue(ValueSizeProperty, value); }
}

public enum AvoState { Ok, Warning, Error, Info, Unknown }

/// <summary>Coloured dot + text, colours of Android (Ok #52DD40, Warn #FFC42C, Bad #FF3945, Info #3D9BFF, Unknown #93949B).</summary>
public class AvoStatusIndicator : Control
{
    public static readonly DependencyProperty StateProperty = DependencyProperty.Register(nameof(State), typeof(AvoState), typeof(AvoStatusIndicator), new PropertyMetadata(AvoState.Unknown));
    public static readonly DependencyProperty TextProperty = DependencyProperty.Register(nameof(Text), typeof(string), typeof(AvoStatusIndicator), new PropertyMetadata(""));
    public static readonly DependencyProperty DetailProperty = DependencyProperty.Register(nameof(Detail), typeof(string), typeof(AvoStatusIndicator), new PropertyMetadata(""));
    public AvoState State { get => (AvoState)GetValue(StateProperty); set => SetValue(StateProperty, value); }
    public string Text { get => (string)GetValue(TextProperty); set => SetValue(TextProperty, value); }
    public string Detail { get => (string)GetValue(DetailProperty); set => SetValue(DetailProperty, value); }
}

/// <summary>Card for a chart: title, legend/tools on the right, chart content.</summary>
public class AvoChartPanel : HeaderedContentControl
{
    public static readonly DependencyProperty LegendProperty = DependencyProperty.Register(nameof(Legend), typeof(object), typeof(AvoChartPanel));
    public static readonly DependencyProperty ReadoutProperty = DependencyProperty.Register(nameof(Readout), typeof(string), typeof(AvoChartPanel), new PropertyMetadata(""));
    public object? Legend { get => GetValue(LegendProperty); set => SetValue(LegendProperty, value); }
    public string Readout { get => (string)GetValue(ReadoutProperty); set => SetValue(ReadoutProperty, value); }
}

/// <summary>Toolbar floating over the map (layers, zoom, fit).</summary>
public class AvoMapToolbar : ItemsControl { }

/// <summary>Coloured legend entry (line sample + text).</summary>
public class AvoLegendItem : Control
{
    public static readonly DependencyProperty TextProperty = DependencyProperty.Register(nameof(Text), typeof(string), typeof(AvoLegendItem), new PropertyMetadata(""));
    public static readonly DependencyProperty SwatchProperty = DependencyProperty.Register(nameof(Swatch), typeof(Brush), typeof(AvoLegendItem));
    public string Text { get => (string)GetValue(TextProperty); set => SetValue(TextProperty, value); }
    public Brush? Swatch { get => (Brush?)GetValue(SwatchProperty); set => SetValue(SwatchProperty, value); }
}

/// <summary>Label/value row used in the information panels.</summary>
public class AvoKeyValue : Control
{
    public static readonly DependencyProperty KeyTextProperty = DependencyProperty.Register(nameof(KeyText), typeof(string), typeof(AvoKeyValue), new PropertyMetadata(""));
    public static readonly DependencyProperty ValueTextProperty = DependencyProperty.Register(nameof(ValueText), typeof(string), typeof(AvoKeyValue), new PropertyMetadata(""));
    public string KeyText { get => (string)GetValue(KeyTextProperty); set => SetValue(KeyTextProperty, value); }
    public string ValueText { get => (string)GetValue(ValueTextProperty); set => SetValue(ValueTextProperty, value); }
}

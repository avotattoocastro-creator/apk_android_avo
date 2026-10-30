using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Data;
using System.Windows.Input;

namespace Avo.Windows.ViewModels;

public abstract class ObservableObject : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    protected bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        Raise(name);
        return true;
    }
    protected void Raise([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    protected void RaiseMany(params string[] names) { foreach (var n in names) Raise(n); }
}

public sealed class RelayCommand : ICommand
{
    private readonly Action<object?> _run;
    private readonly Func<object?, bool>? _can;
    public RelayCommand(Action<object?> run, Func<object?, bool>? can = null) { _run = run; _can = can; }
    public RelayCommand(Action run, Func<bool>? can = null) : this(_ => run(), can is null ? null : _ => can()) { }
    public bool CanExecute(object? parameter) => _can?.Invoke(parameter) ?? true;
    public void Execute(object? parameter) => _run(parameter);
    public event EventHandler? CanExecuteChanged { add => CommandManager.RequerySuggested += value; remove => CommandManager.RequerySuggested -= value; }
}

/// <summary>Async command that reports errors through the view model instead of crashing the UI thread.</summary>
public sealed class AsyncCommand : ICommand
{
    private readonly Func<object?, Task> _run;
    private readonly Action<Exception> _onError;
    private bool _busy;
    public AsyncCommand(Func<object?, Task> run, Action<Exception> onError) { _run = run; _onError = onError; }
    public bool CanExecute(object? parameter) => !_busy;
    public async void Execute(object? parameter)
    {
        _busy = true; CommandManager.InvalidateRequerySuggested();
        try { await _run(parameter); }
        catch (Exception ex) { _onError(ex); }
        finally { _busy = false; CommandManager.InvalidateRequerySuggested(); }
    }
    public event EventHandler? CanExecuteChanged { add => CommandManager.RequerySuggested += value; remove => CommandManager.RequerySuggested -= value; }
}

/// <summary>Dialogs requested by the view models (implemented by the window; replaced in capture/test mode).</summary>
public interface IDialogs
{
    string[] OpenTrainingFiles();
    string? OpenFolder();
    string? SaveFile(string filter, string defaultName);
    void Show(string title, string message, bool error = false);
}

public sealed class PageVisibility : IValueConverter
{
    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        string.Equals(value?.ToString(), parameter?.ToString(), StringComparison.Ordinal) ? Visibility.Visible : Visibility.Collapsed;
    public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => Binding.DoNothing;
}

public sealed class NotPageVisibility : IValueConverter
{
    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        string.Equals(value?.ToString(), parameter?.ToString(), StringComparison.Ordinal) ? Visibility.Collapsed : Visibility.Visible;
    public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => Binding.DoNothing;
}

public sealed class BoolVisibility : IValueConverter
{
    public bool Invert { get; set; }
    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        (value is true) ^ Invert ? Visibility.Visible : Visibility.Collapsed;
    public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => Binding.DoNothing;
}

public sealed class NullVisibility : IValueConverter
{
    public bool Invert { get; set; }
    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        (value is null || value is string { Length: 0 }) ^ Invert ? Visibility.Collapsed : Visibility.Visible;
    public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => Binding.DoNothing;
}

/// <summary>RadioButton IsChecked ⇄ string/enum value (parameter).</summary>
public sealed class EqualsConverter : IValueConverter
{
    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        string.Equals(value?.ToString(), parameter?.ToString(), StringComparison.Ordinal);
    public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        if (value is not true) return Binding.DoNothing;
        if (targetType.IsEnum && parameter is string s) return Enum.Parse(targetType, s);
        return parameter;
    }
}

public sealed class ColorBrush : IValueConverter
{
    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        value is System.Windows.Media.Color c ? new System.Windows.Media.SolidColorBrush(c) : System.Windows.Media.Brushes.Transparent;
    public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => Binding.DoNothing;
}

/// <summary>Seconds → m:ss / h:mm:ss.</summary>
public sealed class ClockConverter : IValueConverter
{
    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        value is double d ? Core.TimeText.Clock(d) : "—";
    public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => Binding.DoNothing;
}

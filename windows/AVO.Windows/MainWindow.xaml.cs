using System.IO;
using System.Windows;
using Microsoft.Win32;
using Avo.Windows.ViewModels;

namespace Avo.Windows;

public partial class MainWindow : Window, IDialogs
{
    public MainViewModel ViewModel { get; }

    public MainWindow(MainViewModel vm)
    {
        ViewModel = vm;
        vm.Dialogs = this;
        DataContext = vm;
        InitializeComponent();
        AllowDrop = true;
        Drop += async (_, e) =>
        {
            if (e.Data.GetData(DataFormats.FileDrop) is string[] files)
                await vm.ImportFilesAsync(files.Where(f => f.EndsWith(".avo", StringComparison.OrdinalIgnoreCase) || f.EndsWith(".avr", StringComparison.OrdinalIgnoreCase)));
        };
    }

    public string[] OpenTrainingFiles()
    {
        var d = new OpenFileDialog { Title = "Abrir entrenamientos AVO", Filter = "Entrenamientos AVO (*.avo;*.avr)|*.avo;*.avr", Multiselect = true };
        return d.ShowDialog(this) == true ? d.FileNames : [];
    }

    public string? OpenFolder()
    {
        var d = new OpenFolderDialog { Title = "Carpeta con entrenamientos .avo / .avr" };
        return d.ShowDialog(this) == true ? d.FolderName : null;
    }

    public string? SaveFile(string filter, string defaultName)
    {
        var d = new SaveFileDialog { Filter = filter, FileName = defaultName, InitialDirectory = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments) };
        return d.ShowDialog(this) == true ? d.FileName : null;
    }

    public void Show(string title, string message, bool error = false) =>
        MessageBox.Show(this, message, title, MessageBoxButton.OK, error ? MessageBoxImage.Warning : MessageBoxImage.Information);

    /// <summary>Path helper for the capture mode.</summary>
    public static string EnsureDir(string dir) { Directory.CreateDirectory(dir); return dir; }
}

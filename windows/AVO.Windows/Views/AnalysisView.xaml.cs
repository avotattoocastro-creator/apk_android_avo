using System.Windows;
using System.Windows.Controls;

namespace Avo.Windows.Views;

public partial class AnalysisView : UserControl
{
    public AnalysisView() { InitializeComponent(); }
    private void ZoomIn(object sender, RoutedEventArgs e) => Map.ZoomBy(1);
    private void ZoomOut(object sender, RoutedEventArgs e) => Map.ZoomBy(-1);
    private void Fit(object sender, RoutedEventArgs e) => Map.FitToRoute();
}

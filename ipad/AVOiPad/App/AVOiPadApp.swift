import SwiftUI

@main
struct AVOiPadApp: App {
    /// One model for the whole app (Windows App.OnStartup creates one MainViewModel). In capture mode (-AVOCapture) it
    /// uses a fresh temporary folder and loads the bundled demonstration sessions.
    @State private var app: AppModel = AppModel.launch()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
                .tint(Avo.red)
                .onOpenURL { url in
                    // .avo / .avr opened from Files, AirDrop or the share sheet
                    Task { @MainActor in await app.importURLs([url]) }
                }
        }
    }
}

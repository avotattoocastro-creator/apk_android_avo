import SwiftUI

@main
struct AVOiPadApp: App {
    /// One model for the whole app (Windows App.OnStartup creates one MainViewModel). In capture mode (-AVOCapture) it
    /// uses a fresh temporary folder and loads the bundled demonstration sessions.
    @State private var app: AppModel = AppModel.launch()
    @Environment(\.scenePhase) private var scenePhase

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
                .onChange(of: scenePhase) { (_: ScenePhase, phase: ScenePhase) in
                    // copy to «AVO Horse» when leaving the app (a few seconds of background time)
                    if phase == .background {
                        let bg: UIBackgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "avo.copia", expirationHandler: nil)
                        Task { @MainActor in
                            await app.syncDocuments()
                            UIApplication.shared.endBackgroundTask(bg)
                        }
                    } else if phase == .active {
                        app.scheduleDocumentsSync(delay: 2)
                    }
                }
        }
    }
}

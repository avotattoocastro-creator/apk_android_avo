import SwiftUI

@main
struct AVOiPadApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Avo.red)
        }
    }
}

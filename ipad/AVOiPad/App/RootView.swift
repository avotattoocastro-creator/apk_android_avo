import SwiftUI
struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("AVO Horse").font(.largeTitle)
            Text(String(cString: avo_eq_version())).foregroundStyle(Avo.textDim)
        }
    }
}

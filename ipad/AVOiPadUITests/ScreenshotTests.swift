import XCTest

/// Visual evidence for CI (like the Windows --capture mode): launches the real app with the bundled DEMONSTRATION
/// sessions and takes a screenshot of every page, in landscape and portrait, on the iPad Pro 13-inch (M4) simulator.
/// Screenshots go to the folder in the AVO_SHOTS environment variable (TEST_RUNNER_AVO_SHOTS in xcodebuild) and are
/// also attached to the result bundle.
final class ScreenshotTests: XCTestCase {
    /// (identifier, is a tab of the training bar). Sidebar = general pages; «Análisis» opens the training and its pages
    /// are in the training bar at the top.
    static let pages: [(String, Bool)] = [("Home", false), ("Sessions", false), ("List", false), ("Races", false), ("Stable", false),
                                          ("Riders", false), ("Analysis", false), ("Summary", true), ("Charts", true), ("Segments", true),
                                          ("Gps", true), ("Biomech", true), ("Compare", true), ("Tides", true), ("Reports", true),
                                          ("Engine", true), ("Geofences", false), ("WatchWifi", false), ("Server", false)]

    override func setUp() { continueAfterFailure = true }

    func testCaptureEveryPageLandscape() throws { try capture(orientation: .landscapeLeft, suffix: "horizontal") }
    func testCaptureEveryPagePortrait() throws { try capture(orientation: .portrait, suffix: "vertical") }

    private func capture(orientation: UIDeviceOrientation, suffix: String) throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AVOCapture", "1"]
        app.launch()
        XCUIDevice.shared.orientation = orientation
        // the capture mode imports the demo sessions and runs the engine before showing the ready marker
        _ = app.otherElements["capture.ready"].waitForExistence(timeout: 240) || app.staticTexts["capture.ready"].waitForExistence(timeout: 5)
        for (i, entry) in Self.pages.enumerated() {
            let (page, isTab) = entry
            let nav = app.buttons[(isTab ? "tab." : "nav.") + page]
            if !isTab && !nav.waitForExistence(timeout: 4) {
                // the start screen hides the sidebar: its «Menú» button shows it again
                let menu = app.buttons["start.menu"]
                if menu.exists {
                    menu.tap()
                } else {
                    // compact width: the sidebar may be hidden behind its toggle
                    let toggle = app.buttons["ToggleSidebar"]
                    if toggle.exists { toggle.tap() }
                }
            }
            guard nav.waitForExistence(timeout: 5) else { XCTFail("No existe \(isTab ? "tab" : "nav").\(page)"); continue }
            // narrow screens: the training bar scrolls horizontally
            var tries = 0
            while isTab && !nav.isHittable && tries < 4 {
                let bar = app.scrollViews["training.tabs"]
                if bar.exists { bar.swipeLeft() }
                tries += 1
            }
            nav.tap()
            Thread.sleep(forTimeInterval: page == "Analysis" || page == "Geofences" ? 6 : 2)
            save(app, name: String(format: "%02d_%@_%@", i + 1, page, suffix))
        }
    }

    private func save(_ app: XCUIApplication, name: String) {
        let shot = XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: shot)
        att.name = name
        att.lifetime = .keepAlways
        add(att)
        if let dir = ProcessInfo.processInfo.environment["AVO_SHOTS"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
    }
}

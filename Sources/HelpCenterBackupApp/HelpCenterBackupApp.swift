import SwiftUI

@main
struct HelpCenterBackupApp: App {
    private let fixedWindowSize = CGSize(width: 1200, height: 800)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: fixedWindowSize.width, height: fixedWindowSize.height)
        }
        .defaultSize(width: fixedWindowSize.width, height: fixedWindowSize.height)
        .windowResizability(.contentSize)
    }
}

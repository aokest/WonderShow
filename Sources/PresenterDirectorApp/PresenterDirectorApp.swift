import PresenterDirector
import SwiftUI

@main
struct PresenterDirectorApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .frame(minWidth: 1040, minHeight: 680)
        }
        .windowStyle(.titleBar)
    }
}

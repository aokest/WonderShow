import PresenterDirector
import SwiftUI

@main
struct PresenterDirectorApp: App {
    var body: some Scene {
        Window("灵演", id: "main") {
            DashboardView()
                .frame(minWidth: 1120, minHeight: 720)
        }
        .windowStyle(.titleBar)
    }
}

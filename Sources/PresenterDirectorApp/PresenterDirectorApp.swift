import PresenterDirector
import SwiftUI

@main
struct PresenterDirectorApp: App {
    var body: some Scene {
        Window("灵演", id: "main") {
            DashboardView()
                .frame(minWidth: 1280, minHeight: 780)
        }
        .windowStyle(.titleBar)
    }
}

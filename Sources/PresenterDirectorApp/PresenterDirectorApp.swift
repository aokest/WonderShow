import PresenterDirector
import SwiftUI

@main
struct PresenterDirectorApp: App {
    @NSApplicationDelegateAdaptor(WonderShowAppCoordinator.self) private var coordinator

    var body: some Scene {
        Window("灵演", id: "main") {
            DashboardView(controlCenter: coordinator.controlCenter)
                .frame(minWidth: 1280, minHeight: 780)
        }
        .windowStyle(.titleBar)
    }
}

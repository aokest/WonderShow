import WonderShow
import SwiftUI

@main
struct WonderShowApp: App {
    @NSApplicationDelegateAdaptor(WonderShowAppCoordinator.self) private var coordinator

    var body: some Scene {
        Window(WonderShowDistribution.windowTitle, id: "main") {
            DashboardView(controlCenter: coordinator.controlCenter)
                .frame(minWidth: 1280, minHeight: 780)
        }
        .windowStyle(.titleBar)
    }
}

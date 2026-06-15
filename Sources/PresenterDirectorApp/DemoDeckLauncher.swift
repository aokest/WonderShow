import AppKit

enum DemoDeckLauncher {
    @discardableResult
    static func openDemoDeck() -> Result<URL, Error> {
        do {
            try DemoControlServer.shared.start()
            let url = DemoControlServer.shared.demoURL
            openInChrome(url)
            return .success(url)
        } catch {
            if let fallback = candidateURLs().first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                openInChrome(fallback)
            }
            return .failure(error)
        }
    }

    private static func openInChrome(_ url: URL) {
        guard let chromeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
            NSWorkspace.shared.open(url)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: chromeURL, configuration: configuration)
    }

    private static func candidateURLs() -> [URL] {
        let bundleURL = Bundle.main.bundleURL
        return [
            Bundle.main.url(forResource: "wondershow-demo", withExtension: "html"),
            URL(fileURLWithPath: "/Users/aoke/code test/视频直播设备/examples/wondershow-demo.html"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("examples/wondershow-demo.html"),
            bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("examples/wondershow-demo.html")
        ].compactMap { $0 }
    }
}

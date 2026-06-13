import AppKit

enum DemoDeckLauncher {
    static func openDemoDeck() {
        for candidate in candidateURLs() where FileManager.default.fileExists(atPath: candidate.path) {
            NSWorkspace.shared.open(candidate)
            return
        }
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

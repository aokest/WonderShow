import Foundation
import PresenterDirector

enum RecordingProjectStoreError: Error, LocalizedError {
    case missingManifest(URL)
    case missingProgramExport(URL)
    case sameSourceAndDestination(URL)

    var errorDescription: String? {
        switch self {
        case .missingManifest(let url):
            return "未找到项目文件：\(url.path)"
        case .missingProgramExport(let url):
            return "合成视频尚未生成：\(url.path)"
        case .sameSourceAndDestination(let url):
            return "导出位置不能与源文件相同：\(url.path)"
        }
    }
}

struct RecordingProjectStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load(from selectedURL: URL) throws -> RecordingSessionRecord {
        let isManifestFile = selectedURL.pathExtension.lowercased() == "json"
        let projectURL = isManifestFile
            ? selectedURL.deletingLastPathComponent()
            : selectedURL
        let manifestURL = isManifestFile
            ? selectedURL
            : projectURL.appendingPathComponent("project.json")

        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw RecordingProjectStoreError.missingManifest(manifestURL)
        }

        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(RecordingProjectManifest.self, from: data)
        return RecordingSessionRecord(
            url: projectURL,
            manifestURL: manifestURL,
            presenterCameraURL: projectURL.appendingPathComponent("Raw/presenter-camera.mov"),
            slidesScreenURL: projectURL.appendingPathComponent("Raw/slides-screen.mov"),
            microphoneAudioURL: projectURL.appendingPathComponent("Raw/microphone.m4a"),
            programOutputURL: projectURL.appendingPathComponent("Exports/program.mp4"),
            manifest: manifest
        )
    }

    func copyProject(session: RecordingSessionRecord, to destinationURL: URL) throws {
        guard normalized(session.url) != normalized(destinationURL) else {
            throw RecordingProjectStoreError.sameSourceAndDestination(destinationURL)
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: session.url, to: destinationURL)
    }

    func copyProgramExport(session: RecordingSessionRecord, to destinationURL: URL) throws {
        guard fileManager.fileExists(atPath: session.programOutputURL.path) else {
            throw RecordingProjectStoreError.missingProgramExport(session.programOutputURL)
        }
        guard normalized(session.programOutputURL) != normalized(destinationURL) else {
            throw RecordingProjectStoreError.sameSourceAndDestination(destinationURL)
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: session.programOutputURL, to: destinationURL)
    }

    private func normalized(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}

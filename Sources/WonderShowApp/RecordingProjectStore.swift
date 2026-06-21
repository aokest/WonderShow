import Foundation
import WonderShow

enum RecordingProjectStoreError: Error, LocalizedError {
    case missingManifest(URL)
    case manifestTooLarge(URL, Int64)
    case unsupportedSchemaVersion(Int)
    case missingProgramExport(URL)
    case sameSourceAndDestination(URL)
    case unsafeMediaAssetPath(String)
    case unsafeExportDestination(URL)

    var errorDescription: String? {
        switch self {
        case .missingManifest(let url):
            return "未找到项目文件：\(url.path)"
        case .manifestTooLarge(let url, let size):
            return "项目文件过大，已拒绝导入：\(url.path)（\(size) 字节）"
        case .unsupportedSchemaVersion(let version):
            return "不支持的项目 schemaVersion：\(version)"
        case .missingProgramExport(let url):
            return "合成视频尚未生成：\(url.path)"
        case .sameSourceAndDestination(let url):
            return "导出位置不能与源文件相同：\(url.path)"
        case .unsafeMediaAssetPath(let path):
            return "项目包含不安全的媒体路径，已拒绝导入：\(path)"
        case .unsafeExportDestination(let url):
            return "导出位置不安全，已拒绝写入：\(url.path)"
        }
    }
}

struct RecordingProjectStore {
    private static let maximumManifestSizeBytes: Int64 = 2 * 1_024 * 1_024
    private static let supportedSchemaVersions: Set<Int> = [1]

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

        let manifestSize = (try fileManager.attributesOfItem(atPath: manifestURL.path)[.size] as? NSNumber)?
            .int64Value ?? 0
        guard manifestSize <= Self.maximumManifestSizeBytes else {
            throw RecordingProjectStoreError.manifestTooLarge(manifestURL, manifestSize)
        }

        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(RecordingProjectManifest.self, from: data)
        guard Self.supportedSchemaVersions.contains(manifest.schemaVersion) else {
            throw RecordingProjectStoreError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
        try validateMediaAssetPaths(manifest.mediaAssets)
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
        try validateExportDestination(destinationURL)
        guard normalized(session.url) != normalized(destinationURL) else {
            throw RecordingProjectStoreError.sameSourceAndDestination(destinationURL)
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: session.url, to: destinationURL)
    }

    func copyProgramExport(session: RecordingSessionRecord, to destinationURL: URL) throws {
        try validateExportDestination(destinationURL)
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

    private func validateMediaAssetPaths(_ assets: [RecordingMediaAsset]) throws {
        for asset in assets where !Self.isSafeRelativePath(asset.relativePath) {
            throw RecordingProjectStoreError.unsafeMediaAssetPath(asset.relativePath)
        }
    }

    private func validateExportDestination(_ url: URL) throws {
        guard url.isFileURL, !url.hasDirectoryPath else {
            throw RecordingProjectStoreError.unsafeExportDestination(url)
        }
        let fileName = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fileName.isEmpty, fileName != "." && fileName != ".." else {
            throw RecordingProjectStoreError.unsafeExportDestination(url)
        }
    }

    private static func isSafeRelativePath(_ relativePath: String) -> Bool {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.hasPrefix("/") && !trimmed.hasPrefix("~") else { return false }
        guard !trimmed.contains("\\") else { return false }

        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }
}

import Foundation

public enum WonderShowPluginAPI {
    public static let version = "0.1.0"
}

public struct WonderShowPluginManifest: Codable, Equatable, Sendable {
    public var identifier: String
    public var displayName: String
    public var vendor: String
    public var version: String
    public var apiVersion: String
    public var capabilities: [WonderShowPluginCapability]

    public init(
        identifier: String,
        displayName: String,
        vendor: String,
        version: String,
        apiVersion: String = WonderShowPluginAPI.version,
        capabilities: [WonderShowPluginCapability]
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.vendor = vendor
        self.version = version
        self.apiVersion = apiVersion
        self.capabilities = capabilities
    }
}

public enum WonderShowPluginCapability: String, Codable, CaseIterable, Sendable {
    case effectCatalog
    case inputSource
    case exportDestination
    case manifestTransform
}

public protocol WonderShowPlugin: Sendable {
    var manifest: WonderShowPluginManifest { get }
}

public protocol WonderShowEffectCatalogPlugin: WonderShowPlugin {
    func describeEffects(context: WonderShowPluginContext) async throws -> [WonderShowEffectDescriptor]
}

public protocol WonderShowInputSourcePlugin: WonderShowPlugin {
    func listSources(context: WonderShowPluginContext) async throws -> [WonderShowInputSourceDescriptor]
}

public protocol WonderShowExportDestinationPlugin: WonderShowPlugin {
    func export(
        manifest: WonderShowProjectManifest,
        request: WonderShowExportRequest,
        context: WonderShowPluginContext
    ) async throws -> WonderShowExportResult
}

public protocol WonderShowManifestTransformPlugin: WonderShowPlugin {
    func transform(
        manifest: WonderShowProjectManifest,
        context: WonderShowPluginContext
    ) async throws -> WonderShowProjectManifest
}

public struct WonderShowPluginContext: Sendable {
    public var hostAppVersion: String
    public var projectDirectory: URL?
    public var environment: [String: String]

    public init(
        hostAppVersion: String,
        projectDirectory: URL? = nil,
        environment: [String: String] = [:],
        allowedEnvironmentKeys: Set<String> = []
    ) {
        self.hostAppVersion = hostAppVersion
        self.projectDirectory = projectDirectory
        self.environment = environment.filter { allowedEnvironmentKeys.contains($0.key) }
    }
}

public struct WonderShowEffectDescriptor: Codable, Equatable, Sendable {
    public var identifier: String
    public var displayName: String
    public var category: WonderShowEffectCategory
    public var parameters: [WonderShowEffectParameter]

    public init(
        identifier: String,
        displayName: String,
        category: WonderShowEffectCategory,
        parameters: [WonderShowEffectParameter]
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.category = category
        self.parameters = parameters
    }
}

public enum WonderShowEffectCategory: String, Codable, CaseIterable, Sendable {
    case presenterBeauty
    case background
    case faceReplacement
    case annotation
    case export
}

public struct WonderShowEffectParameter: Codable, Equatable, Sendable {
    public var identifier: String
    public var displayName: String
    public var valueKind: WonderShowPluginValueKind
    public var defaultValue: String?

    public init(
        identifier: String,
        displayName: String,
        valueKind: WonderShowPluginValueKind,
        defaultValue: String? = nil
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.valueKind = valueKind
        self.defaultValue = defaultValue
    }
}

public enum WonderShowPluginValueKind: String, Codable, CaseIterable, Sendable {
    case boolean
    case number
    case text
    case assetReference
}

public struct WonderShowInputSourceDescriptor: Codable, Equatable, Sendable {
    public var identifier: String
    public var displayName: String
    public var kind: WonderShowInputKind

    public init(identifier: String, displayName: String, kind: WonderShowInputKind) {
        self.identifier = identifier
        self.displayName = displayName
        self.kind = kind
    }
}

public struct WonderShowExportRequest: Codable, Equatable, Sendable {
    public var destinationURL: URL
    public var settings: WonderShowExportSettings

    public init(destinationURL: URL, settings: WonderShowExportSettings) {
        self.destinationURL = destinationURL
        self.settings = settings
    }
}

public struct WonderShowExportResult: Codable, Equatable, Sendable {
    public var outputURL: URL
    public var durationMilliseconds: Int
    public var warnings: [String]

    public init(outputURL: URL, durationMilliseconds: Int, warnings: [String] = []) {
        self.outputURL = outputURL
        self.durationMilliseconds = durationMilliseconds
        self.warnings = warnings
    }
}

public enum WonderShowPluginPathSecurityError: Error, Equatable, Sendable {
    case destinationEscapesAllowedDirectory(URL)
    case destinationIsDirectory(URL)
}

public enum WonderShowPluginPathSecurity {
    public static func authorizedDestinationURL(
        _ destinationURL: URL,
        allowedDirectory: URL
    ) throws -> URL {
        let allowedRoot = allowedDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let destination = destinationURL.standardizedFileURL.resolvingSymlinksInPath()

        guard destination.isContained(in: allowedRoot) else {
            throw WonderShowPluginPathSecurityError.destinationEscapesAllowedDirectory(destinationURL)
        }
        guard !destination.hasDirectoryPath else {
            throw WonderShowPluginPathSecurityError.destinationIsDirectory(destinationURL)
        }
        return destination
    }
}

private extension URL {
    func isContained(in directory: URL) -> Bool {
        let path = standardizedFileURL.path
        let directoryPath = directory.standardizedFileURL.path
        return path == directoryPath || path.hasPrefix(directoryPath + "/")
    }
}

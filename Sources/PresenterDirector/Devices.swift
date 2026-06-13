public enum CaptureInterface: Hashable, Sendable {
    case uvcCamera
    case avFoundationDevice
}

public enum TrackingMode: Hashable, Sendable {
    case hardwareFaceTrackConfiguredOnDevice
    case softwareCropFromVideoStream
    case none
}

public struct DeviceCapability: Hashable, Sendable {
    public let name: String
    public let captureInterface: CaptureInterface
    public let requiresPrivateGimbalSDK: Bool
    public let recommendedTrackingMode: TrackingMode

    public init(
        name: String,
        captureInterface: CaptureInterface,
        requiresPrivateGimbalSDK: Bool,
        recommendedTrackingMode: TrackingMode
    ) {
        self.name = name
        self.captureInterface = captureInterface
        self.requiresPrivateGimbalSDK = requiresPrivateGimbalSDK
        self.recommendedTrackingMode = recommendedTrackingMode
    }

    public static let pocket3 = DeviceCapability(
        name: "DJI Osmo Pocket 3",
        captureInterface: .uvcCamera,
        requiresPrivateGimbalSDK: false,
        recommendedTrackingMode: .hardwareFaceTrackConfiguredOnDevice
    )
}

public enum CaptureInterface: Hashable, Sendable {
    case uvcCamera
    case avFoundationDevice
    case networkStream
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

    public static let builtInCamera = DeviceCapability(
        name: "Mac 内置摄像头",
        captureInterface: .avFoundationDevice,
        requiresPrivateGimbalSDK: false,
        recommendedTrackingMode: .softwareCropFromVideoStream
    )

    public static func uvcCamera(name: String, trackingMode: TrackingMode = .softwareCropFromVideoStream) -> DeviceCapability {
        DeviceCapability(
            name: name,
            captureInterface: .uvcCamera,
            requiresPrivateGimbalSDK: false,
            recommendedTrackingMode: trackingMode
        )
    }

    public static func networkCamera(name: String) -> DeviceCapability {
        DeviceCapability(
            name: name,
            captureInterface: .networkStream,
            requiresPrivateGimbalSDK: false,
            recommendedTrackingMode: .softwareCropFromVideoStream
        )
    }

    public static let supportedExamples: [DeviceCapability] = [
        .pocket3,
        .uvcCamera(name: "Insta360 摄像头 / 运动相机"),
        .builtInCamera,
        .uvcCamera(name: "USB 采集卡 / HDMI 相机"),
        .networkCamera(name: "海康威视网络摄像头")
    ]
}

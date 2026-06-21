import Foundation

public enum WonderShowMediaPipeProtocol {
    public static let defaultPort = 18777
    public static let loopbackHost = "127.0.0.1"
    public static let healthPath = "/health"
    public static let inferPath = "/infer"
    public static let localTokenHeader = "X-WonderShow-Local-Token"
    public static let minimumTokenBytes = 16
    public static let maximumTokenBytes = 256
    public static let maximumJPEGBytes = 6 * 1_024 * 1_024
    public static let maximumPortraitMaskPixels = 512 * 512
    public static let maximumLandmarkCount = 512
}

public struct WonderShowMediaPipeHealth: Codable, Equatable, Sendable {
    public var ok: Bool
    public var version: String
    public var models: [String]

    public init(ok: Bool, version: String, models: [String]) {
        self.ok = ok
        self.version = version
        self.models = models
    }
}

public struct WonderShowMediaPipeInferRequest: Codable, Equatable, Sendable {
    public var frameId: String
    public var timestampMilliseconds: Int
    public var imageBase64JPEG: String
    public var tasks: [WonderShowMediaPipeTask]

    public init(
        frameId: String,
        timestampMilliseconds: Int,
        imageBase64JPEG: String,
        tasks: [WonderShowMediaPipeTask]
    ) {
        self.frameId = frameId
        self.timestampMilliseconds = timestampMilliseconds
        self.imageBase64JPEG = imageBase64JPEG
        self.tasks = tasks
    }

    private enum CodingKeys: String, CodingKey {
        case frameId = "frame_id"
        case timestampMilliseconds = "timestamp_ms"
        case imageBase64JPEG = "image_base64_jpeg"
        case tasks
    }
}

public enum WonderShowMediaPipeTask: String, Codable, CaseIterable, Sendable {
    case handLandmarks = "hand_landmarks"
    case faceLandmarks = "face_landmarks"
    case portraitSegmentation = "portrait_segmentation"
}

public struct WonderShowMediaPipeInferResponse: Codable, Equatable, Sendable {
    public var frameId: String
    public var timestampMilliseconds: Int
    public var hands: [WonderShowMediaPipeHandPrediction]
    public var faces: [WonderShowMediaPipeFacePrediction]
    public var portrait: WonderShowMediaPipePortraitPrediction?

    public init(
        frameId: String,
        timestampMilliseconds: Int,
        hands: [WonderShowMediaPipeHandPrediction] = [],
        faces: [WonderShowMediaPipeFacePrediction] = [],
        portrait: WonderShowMediaPipePortraitPrediction? = nil
    ) {
        self.frameId = frameId
        self.timestampMilliseconds = timestampMilliseconds
        self.hands = hands
        self.faces = faces
        self.portrait = portrait
    }

    private enum CodingKeys: String, CodingKey {
        case frameId = "frame_id"
        case timestampMilliseconds = "timestamp_ms"
        case hands
        case faces
        case portrait
    }
}

public struct WonderShowMediaPipeHandPrediction: Codable, Equatable, Sendable {
    public var handedness: String
    public var confidence: Double
    public var landmarks: [WonderShowMediaPipeLandmark]

    public init(handedness: String, confidence: Double, landmarks: [WonderShowMediaPipeLandmark]) {
        self.handedness = handedness
        self.confidence = confidence
        self.landmarks = landmarks
    }
}

public struct WonderShowMediaPipeFacePrediction: Codable, Equatable, Sendable {
    public var confidence: Double
    public var boundingBox: WonderShowMediaPipeBoundingBox
    public var landmarks: [WonderShowMediaPipeLandmark]

    public init(
        confidence: Double,
        boundingBox: WonderShowMediaPipeBoundingBox,
        landmarks: [WonderShowMediaPipeLandmark]
    ) {
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.landmarks = landmarks
    }

    private enum CodingKeys: String, CodingKey {
        case confidence
        case boundingBox = "bounding_box"
        case landmarks
    }
}

public struct WonderShowMediaPipePortraitPrediction: Codable, Equatable, Sendable {
    public var maskWidth: Int
    public var maskHeight: Int
    public var maskBase64Float32LE: String

    public init(maskWidth: Int, maskHeight: Int, maskBase64Float32LE: String) {
        self.maskWidth = maskWidth
        self.maskHeight = maskHeight
        self.maskBase64Float32LE = maskBase64Float32LE
    }

    private enum CodingKeys: String, CodingKey {
        case maskWidth = "mask_width"
        case maskHeight = "mask_height"
        case maskBase64Float32LE = "mask_base64_float32_le"
    }
}

public struct WonderShowMediaPipeLandmark: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double?
    public var visibility: Double?

    public init(x: Double, y: Double, z: Double? = nil, visibility: Double? = nil) {
        self.x = x
        self.y = y
        self.z = z
        self.visibility = visibility
    }
}

public struct WonderShowMediaPipeBoundingBox: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum WonderShowMediaPipeSecurityError: Error, Equatable, Sendable {
    case invalidLocalToken
    case invalidBase64Image
    case oversizedImagePayload(decodedBytes: Int, maximumBytes: Int)
    case invalidPortraitMaskDimensions(width: Int, height: Int)
    case tooManyLandmarks(count: Int, maximum: Int)
}

public enum WonderShowMediaPipeSecurity {
    public static func isPlausibleLocalToken(_ token: String) -> Bool {
        let byteCount = token.utf8.count
        return byteCount >= WonderShowMediaPipeProtocol.minimumTokenBytes
            && byteCount <= WonderShowMediaPipeProtocol.maximumTokenBytes
    }

    public static func validateLocalToken(_ token: String) throws {
        guard isPlausibleLocalToken(token) else {
            throw WonderShowMediaPipeSecurityError.invalidLocalToken
        }
    }

    public static func validate(_ request: WonderShowMediaPipeInferRequest) throws {
        guard let imageData = Data(base64Encoded: request.imageBase64JPEG) else {
            throw WonderShowMediaPipeSecurityError.invalidBase64Image
        }
        guard imageData.count <= WonderShowMediaPipeProtocol.maximumJPEGBytes else {
            throw WonderShowMediaPipeSecurityError.oversizedImagePayload(
                decodedBytes: imageData.count,
                maximumBytes: WonderShowMediaPipeProtocol.maximumJPEGBytes
            )
        }
    }

    public static func validate(_ response: WonderShowMediaPipeInferResponse) throws {
        for hand in response.hands where hand.landmarks.count > WonderShowMediaPipeProtocol.maximumLandmarkCount {
            throw WonderShowMediaPipeSecurityError.tooManyLandmarks(
                count: hand.landmarks.count,
                maximum: WonderShowMediaPipeProtocol.maximumLandmarkCount
            )
        }
        for face in response.faces where face.landmarks.count > WonderShowMediaPipeProtocol.maximumLandmarkCount {
            throw WonderShowMediaPipeSecurityError.tooManyLandmarks(
                count: face.landmarks.count,
                maximum: WonderShowMediaPipeProtocol.maximumLandmarkCount
            )
        }
        if let portrait = response.portrait {
            guard portrait.maskWidth > 0,
                  portrait.maskHeight > 0,
                  portrait.maskWidth * portrait.maskHeight <= WonderShowMediaPipeProtocol.maximumPortraitMaskPixels else {
                throw WonderShowMediaPipeSecurityError.invalidPortraitMaskDimensions(
                    width: portrait.maskWidth,
                    height: portrait.maskHeight
                )
            }
        }
    }
}

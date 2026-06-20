import CoreImage
import Foundation
import ImageIO
import WonderShow
import UniformTypeIdentifiers

enum GestureEngineBackend: String {
    case visionLegacy = "Vision 增强版"
    case mediaPipeSidecar = "MediaPipe Sidecar"
}

struct MediaPipeSidecarHealth: Codable, Sendable {
    let ok: Bool
    let engine: String?
    let modelPath: String?
    let authRequired: Bool?

    enum CodingKeys: String, CodingKey {
        case ok
        case engine
        case modelPath = "model_path"
        case authRequired = "auth_required"
    }
}

private struct MediaPipeSidecarInferRequest: Codable, Sendable {
    let timestampMs: Int
    let imageBase64: String

    enum CodingKeys: String, CodingKey {
        case timestampMs = "timestamp_ms"
        case imageBase64 = "image_base64"
    }
}

private struct MediaPipeSidecarInferResponse: Codable, Sendable {
    let ok: Bool
    let timestampMs: Int
    let hands: [MediaPipeHandPrediction]
    let faces: [MediaPipeFacePrediction]?
    let segmentation: MediaPipePortraitSegmentationMask?

    enum CodingKeys: String, CodingKey {
        case ok
        case timestampMs = "timestamp_ms"
        case hands
        case faces
        case segmentation
    }
}

/// Talks to the local MediaPipe HTTP sidecar running on the same machine.
/// - Important: This client is local-only and never sends images to the public internet.
actor MediaPipeSidecarClient {
    private let session: URLSession
    private let inferURL: URL
    private let healthURL: URL

    init(baseURL: URL = URL(string: "http://127.0.0.1:18777")!) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 0.65
        configuration.timeoutIntervalForResource = 1.2
        session = URLSession(configuration: configuration)
        inferURL = baseURL.appendingPathComponent("infer")
        healthURL = baseURL.appendingPathComponent("health")
    }

    /// Checks whether the local sidecar is alive and serving requests.
    /// - Returns: Decoded health response or `nil` if the sidecar cannot be reached.
    func health() async -> MediaPipeSidecarHealth? {
        do {
            var request = URLRequest(url: healthURL)
            request.setValue(WonderShowLocalSecurity.sharedToken, forHTTPHeaderField: WonderShowLocalSecurity.headerName)
            let (data, _) = try await session.data(for: request)
            return try JSONDecoder().decode(MediaPipeSidecarHealth.self, from: data)
        } catch {
            return nil
        }
    }

    /// Sends a JPEG frame to the local sidecar for inference.
    /// - Parameters:
    ///   - jpegData: JPEG-encoded image bytes.
    ///   - timestampMilliseconds: Frame timestamp.
    /// - Returns: Parsed inference frame or `nil` when the sidecar is unavailable.
    func infer(jpegData: Data, timestampMilliseconds: Int) async -> MediaPipeInferenceFrame? {
        let requestPayload = MediaPipeSidecarInferRequest(
            timestampMs: timestampMilliseconds,
            imageBase64: jpegData.base64EncodedString()
        )
        guard let body = try? JSONEncoder().encode(requestPayload) else {
            return nil
        }

        var request = URLRequest(url: inferURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(WonderShowLocalSecurity.sharedToken, forHTTPHeaderField: WonderShowLocalSecurity.headerName)
        request.httpBody = body

        do {
            let (data, _) = try await session.data(for: request)
            let response = try JSONDecoder().decode(MediaPipeSidecarInferResponse.self, from: data)
            guard response.ok else { return nil }
            return MediaPipeInferenceFrame(
                timestampMilliseconds: response.timestampMs,
                hands: response.hands,
                portrait: MediaPipePortraitFrame(
                    timestampMilliseconds: response.timestampMs,
                    faces: response.faces ?? [],
                    segmentation: response.segmentation
                )
            )
        } catch {
            return nil
        }
    }

    /// Converts a camera frame into JPEG for local HTTP transport.
    /// - Parameters:
    ///   - pixelBuffer: Captured camera pixel buffer.
    ///   - compressionQuality: JPEG compression quality in the `0...1` range.
    /// - Returns: JPEG data suitable for POSTing to the sidecar.
    nonisolated static func jpegData(
        from pixelBuffer: CVPixelBuffer,
        compressionQuality: Double = 0.82
    ) -> Data? {
        let ciContext = CIContext()
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        let destinationData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            destinationData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let options: CFDictionary = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, options)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return destinationData as Data
    }
}

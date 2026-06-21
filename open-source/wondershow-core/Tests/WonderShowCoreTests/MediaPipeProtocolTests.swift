import Foundation
import Testing
@testable import WonderShowCore

@Test func mediaPipeInferRequestUsesStableSnakeCaseWireKeys() throws {
    let request = WonderShowMediaPipeInferRequest(
        frameId: "frame-1",
        timestampMilliseconds: 120,
        imageBase64JPEG: "abc",
        tasks: [.faceLandmarks, .portraitSegmentation]
    )

    let data = try JSONEncoder().encode(request)
    let json = String(data: data, encoding: .utf8) ?? ""

    #expect(json.contains("frame_id"))
    #expect(json.contains("timestamp_ms"))
    #expect(json.contains("image_base64_jpeg"))
    #expect(json.contains("portrait_segmentation"))
}

@Test func mediaPipeInferResponseDecodesFacesAndPortraitMask() throws {
    let json = """
    {
      "frame_id": "frame-7",
      "timestamp_ms": 240,
      "hands": [],
      "faces": [
        {
          "confidence": 0.98,
          "bounding_box": {"x": 0.25, "y": 0.2, "width": 0.3, "height": 0.4},
          "landmarks": [{"x": 0.4, "y": 0.35, "z": 0.01, "visibility": 0.9}]
        }
      ],
      "portrait": {
        "mask_width": 2,
        "mask_height": 2,
        "mask_base64_float32_le": "AAAA"
      }
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(WonderShowMediaPipeInferResponse.self, from: json)

    #expect(response.frameId == "frame-7")
    #expect(response.timestampMilliseconds == 240)
    #expect(response.faces.first?.boundingBox.width == 0.3)
    #expect(response.portrait?.maskWidth == 2)
}

@Test func mediaPipeProtocolDocumentsLocalOnlyDefaults() {
    #expect(WonderShowMediaPipeProtocol.defaultPort == 18_777)
    #expect(WonderShowMediaPipeProtocol.localTokenHeader == "X-WonderShow-Local-Token")
    #expect(WonderShowMediaPipeProtocol.inferPath == "/infer")
    #expect(WonderShowMediaPipeProtocol.loopbackHost == "127.0.0.1")
    #expect(WonderShowMediaPipeProtocol.minimumTokenBytes == 16)
    #expect(WonderShowMediaPipeProtocol.maximumJPEGBytes == 6 * 1_024 * 1_024)
}

@Test func mediaPipeSecurityAcceptsStrongTokensAndRejectsWeakTokens() {
    let strongToken = String(repeating: "a", count: 32)

    #expect(WonderShowMediaPipeSecurity.isPlausibleLocalToken(strongToken))
    #expect(!WonderShowMediaPipeSecurity.isPlausibleLocalToken("short"))
    #expect(!WonderShowMediaPipeSecurity.isPlausibleLocalToken(""))
}

@Test func mediaPipeSecurityRejectsOversizedJPEGPayloads() {
    let safeRequest = WonderShowMediaPipeInferRequest(
        frameId: "frame-safe",
        timestampMilliseconds: 100,
        imageBase64JPEG: Data(repeating: 1, count: 128).base64EncodedString(),
        tasks: [.handLandmarks]
    )
    #expect(throws: Never.self) {
        try WonderShowMediaPipeSecurity.validate(safeRequest)
    }

    let oversizedRequest = WonderShowMediaPipeInferRequest(
        frameId: "frame-large",
        timestampMilliseconds: 100,
        imageBase64JPEG: Data(
            repeating: 1,
            count: WonderShowMediaPipeProtocol.maximumJPEGBytes + 1
        ).base64EncodedString(),
        tasks: [.handLandmarks]
    )
    #expect(throws: WonderShowMediaPipeSecurityError.self) {
        try WonderShowMediaPipeSecurity.validate(oversizedRequest)
    }
}

@Test func mediaPipeSecurityRejectsOversizedPortraitMasks() {
    let response = WonderShowMediaPipeInferResponse(
        frameId: "frame-mask",
        timestampMilliseconds: 100,
        hands: [],
        faces: [],
        portrait: WonderShowMediaPipePortraitPrediction(
            maskWidth: 4096,
            maskHeight: 4096,
            maskBase64Float32LE: "AAAA"
        )
    )

    #expect(throws: WonderShowMediaPipeSecurityError.self) {
        try WonderShowMediaPipeSecurity.validate(response)
    }
}

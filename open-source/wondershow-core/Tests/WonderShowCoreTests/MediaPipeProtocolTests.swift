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
}


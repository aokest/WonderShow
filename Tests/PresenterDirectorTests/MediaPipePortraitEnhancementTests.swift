import Foundation
import Testing
@testable import PresenterDirector

@Test func mediaPipePortraitFrameDecodesFacesAndSegmentationMask() throws {
    let payload = """
    {
      "timestamp_ms": 1234,
      "faces": [
        {
          "confidence": 0.91,
          "bounding_box": {"x": 0.25, "y": 0.18, "width": 0.50, "height": 0.58},
          "landmarks": [
            {"x": 0.40, "y": 0.42, "z": -0.01},
            {"x": 0.60, "y": 0.42, "z": -0.01}
          ],
          "blendshapes": [
            {"name": "jawOpen", "score": 0.22}
          ]
        }
      ],
      "segmentation": {
        "width": 4,
        "height": 2,
        "format": "gray8",
        "mask_base64": "AAAzZpmZzP8="
      }
    }
    """.data(using: .utf8)!

    let frame = try JSONDecoder().decode(MediaPipePortraitFrame.self, from: payload)

    #expect(frame.timestampMilliseconds == 1234)
    #expect(frame.faces.count == 1)
    #expect(frame.faces[0].landmarks.count == 2)
    #expect(frame.faces[0].blendshapes.first?.name == "jawOpen")
    #expect(frame.segmentation?.width == 4)
    #expect(frame.segmentation?.maskData.count == 8)
}

@Test func mediaPipeInferenceFrameKeepsOptionalPortraitFieldsBackwardCompatible() throws {
    let legacyPayload = """
    {
      "timestamp_ms": 77,
      "hands": []
    }
    """.data(using: .utf8)!
    let enhancedPayload = """
    {
      "timestamp_ms": 78,
      "hands": [],
      "faces": [
        {
          "confidence": 0.88,
          "bounding_box": {"x": 0.1, "y": 0.2, "width": 0.3, "height": 0.4},
          "landmarks": [],
          "blendshapes": []
        }
      ],
      "segmentation": {
        "width": 1,
        "height": 1,
        "format": "gray8",
        "mask_base64": "/w=="
      }
    }
    """.data(using: .utf8)!

    let legacyFrame = try JSONDecoder().decode(MediaPipeInferenceFrame.self, from: legacyPayload)
    let enhancedFrame = try JSONDecoder().decode(MediaPipeInferenceFrame.self, from: enhancedPayload)

    #expect(legacyFrame.portrait.faces.isEmpty)
    #expect(legacyFrame.portrait.segmentation == nil)
    #expect(enhancedFrame.portrait.faces.count == 1)
    #expect(enhancedFrame.portrait.segmentation?.maskData == Data([255]))
}

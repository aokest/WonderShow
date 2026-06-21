@testable import WonderShowApp
@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import Testing

@Suite(.serialized)
struct CameraArchiveRecorderTests {
    @Test func cameraArchiveAspectFillCropsWideFramesToTargetAspect() {
        let cropRect = CameraArchiveFrameGeometry.aspectFillCropRect(
            sourceSize: CGSize(width: 1280, height: 720),
            targetSize: CGSize(width: 640, height: 640)
        )

        #expect(cropRect.origin.x == 280)
        #expect(cropRect.origin.y == 0)
        #expect(cropRect.width == 720)
        #expect(cropRect.height == 720)
    }

    @Test func cameraArchiveKeepsInitialCanvasAndPadsSwitchGaps() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("wondershow-camera-archive-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: rootURL)
        }

        let outputURL = rootURL.appendingPathComponent("presenter-camera.mov")
        let recorder = CameraArchiveRecorder()
        try recorder.startRecording(to: outputURL)
        recorder.append(try makeCameraArchiveSampleBuffer(width: 640, height: 360, red: 220))
        try await Task.sleep(for: .milliseconds(160))
        recorder.append(try makeCameraArchiveSampleBuffer(width: 360, height: 640, red: 90))
        try await Task.sleep(for: .milliseconds(160))
        await withCheckedContinuation { continuation in
            recorder.stopRecording { _ in
                continuation.resume()
            }
        }

        let asset = AVURLAsset(url: outputURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let videoTrack = try #require(tracks.first)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let duration = try await asset.load(.duration)

        #expect(Int(naturalSize.width.rounded()) == 640)
        #expect(Int(naturalSize.height.rounded()) == 360)
        #expect(duration.seconds >= 0.20)
    }
}

private func makeCameraArchiveSampleBuffer(width: Int, height: Int, red: UInt8) throws -> CMSampleBuffer {
    var pixelBuffer: CVPixelBuffer?
    CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        nil,
        &pixelBuffer
    )
    let buffer = try #require(pixelBuffer)
    CVPixelBufferLockBaseAddress(buffer, [])
    defer {
        CVPixelBufferUnlockBaseAddress(buffer, [])
    }

    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    let pointer = try #require(CVPixelBufferGetBaseAddress(buffer))
        .assumingMemoryBound(to: UInt8.self)
    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * 4
            pointer[offset] = 32
            pointer[offset + 1] = 96
            pointer[offset + 2] = red
            pointer[offset + 3] = 255
        }
    }

    var formatDescription: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: buffer,
        formatDescriptionOut: &formatDescription
    )
    let description = try #require(formatDescription)
    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 30),
        presentationTimeStamp: .zero,
        decodeTimeStamp: .invalid
    )
    var sampleBuffer: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: buffer,
        formatDescription: description,
        sampleTiming: &timing,
        sampleBufferOut: &sampleBuffer
    )
    return try #require(sampleBuffer)
}

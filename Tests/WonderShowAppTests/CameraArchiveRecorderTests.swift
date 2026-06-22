@testable import WonderShowApp
@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import Testing

@Suite(.serialized)
struct CameraArchiveRecorderTests {
    @Test func cameraArchiveUpscalesSmallerSwitchedCameraToStableFrame() {
        let rect = CameraArchiveFrameGeometry.centeredAspectFitRect(
            sourceSize: CGSize(width: 640, height: 360),
            targetSize: CGSize(width: 1920, height: 1080)
        )

        #expect(rect.origin.x == 0)
        #expect(rect.origin.y == 0)
        #expect(rect.width == 1920)
        #expect(rect.height == 1080)
    }

    @Test func cameraArchiveFitsPortraitCameraInsideStableLandscapeCanvas() {
        let rect = CameraArchiveFrameGeometry.centeredAspectFitRect(
            sourceSize: CGSize(width: 360, height: 640),
            targetSize: CGSize(width: 640, height: 360)
        )

        #expect(rect.origin.y == 0)
        #expect(rect.height == 360)
        #expect(rect.width < 210)
        #expect(rect.midX == 320)
    }

    @Test func cameraArchiveDetectsDeviceMatteAroundRealCameraContent() throws {
        let sampleBuffer = try makeCameraArchiveSampleBuffer(
            width: 640,
            height: 360,
            red: 220,
            contentRect: CGRect(x: 220, y: 120, width: 200, height: 112)
        )
        let pixelBuffer = try #require(CMSampleBufferGetImageBuffer(sampleBuffer))

        let rect = try #require(CameraFrameMatteDetector.contentRect(in: pixelBuffer))

        #expect(rect.minX > 190)
        #expect(rect.minY > 90)
        #expect(rect.maxX < 450)
        #expect(rect.maxY < 260)
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
        try await Task.sleep(for: .milliseconds(260))
        recorder.append(try makeCameraArchiveSampleBuffer(width: 360, height: 640, red: 90))
        try await Task.sleep(for: .milliseconds(260))
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
        #expect(duration.seconds >= 0.10)
    }

    @Test func cameraArchiveDoesNotEncodePausedWallClockGapAfterDeviceSwitch() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("wondershow-camera-archive-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: rootURL)
        }

        let outputURL = rootURL.appendingPathComponent("presenter-camera-pause.mov")
        let recorder = CameraArchiveRecorder()
        try recorder.startRecording(to: outputURL)
        recorder.append(try makeCameraArchiveSampleBuffer(width: 640, height: 360, red: 220))
        try await Task.sleep(for: .milliseconds(180))
        recorder.pauseRecording()
        try await Task.sleep(for: .milliseconds(360))
        recorder.append(try makeCameraArchiveSampleBuffer(width: 640, height: 360, red: 90))
        try await Task.sleep(for: .milliseconds(120))
        recorder.resumeRecording()
        try await Task.sleep(for: .milliseconds(180))
        await withCheckedContinuation { continuation in
            recorder.stopRecording { _ in
                continuation.resume()
            }
        }

        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration)

        #expect(duration.seconds < 0.62)
        #expect(duration.seconds >= 0.25)
    }
}

private func makeCameraArchiveSampleBuffer(
    width: Int,
    height: Int,
    red: UInt8,
    contentRect: CGRect? = nil
) throws -> CMSampleBuffer {
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
            if let contentRect, !contentRect.contains(CGPoint(x: x, y: y)) {
                pointer[offset] = 0
                pointer[offset + 1] = 0
                pointer[offset + 2] = 0
            } else {
                pointer[offset] = 32
                pointer[offset + 1] = 96
                pointer[offset + 2] = red
            }
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

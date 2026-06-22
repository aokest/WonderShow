@preconcurrency import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import WonderShow

struct ProgramVideoRenderProgress: Equatable, Sendable {
    let fraction: Double
    let width: Int
    let height: Int
    let writtenBytes: Int64
    let outputURL: URL
}

enum ProgramVideoRendererError: Error, LocalizedError {
    case missingCameraTrack
    case missingScreenTrack
    case missingExportSession
    case invalidProgramExport(String)
    case exportFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingCameraTrack:
            return "缺少讲者摄像头原始视频"
        case .missingScreenTrack:
            return "缺少 PPT/屏幕原始视频"
        case .missingExportSession:
            return "无法创建导出会话"
        case .invalidProgramExport(let message):
            return "合成视频不可预览：\(message)"
        case .exportFailed(let message):
            return "program 视频导出失败：\(message)"
        case .cancelled:
            return "视频合成已取消"
        }
    }
}

struct ProgramVideoRenderer {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    private struct VideoSourceSegment {
        let asset: AVURLAsset
        let track: AVAssetTrack
        let duration: CMTime
        let naturalSize: CGSize
    }

    private struct AudioSourceSegment {
        let asset: AVURLAsset
        let track: AVAssetTrack
        let duration: CMTime
    }

    static func validatePlayableVideo(at url: URL, fileManager: FileManager = .default) async throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw ProgramVideoRendererError.invalidProgramExport("文件不存在")
        }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard fileSize > 0 else {
            throw ProgramVideoRendererError.invalidProgramExport("文件为空")
        }

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard duration.isValid, duration.seconds > 0 else {
            throw ProgramVideoRendererError.invalidProgramExport("没有可播放时长")
        }
        guard !videoTracks.isEmpty else {
            throw ProgramVideoRendererError.invalidProgramExport("没有视频轨道")
        }
    }

    func render(
        session: RecordingSessionRecord,
        settings: RecordingExportSettings = .presentationDefault,
        outputURL: URL? = nil,
        selectedRange: TimelineExportRange? = nil,
        progress: (@Sendable (ProgramVideoRenderProgress) -> Void)? = nil
    ) async throws -> URL {
        let timeline = session.manifest.project.timeline
        let requirements = mediaRequirements(for: timeline)
        let cameraSegments = try await videoSourceSegments(
            urls: session.presenterCameraSegmentURLs,
            isRequired: requirements.camera,
            missingError: .missingCameraTrack
        )
        let screenSegments = try await videoSourceSegments(
            urls: session.slidesScreenSegmentURLs,
            isRequired: requirements.screen,
            missingError: .missingScreenTrack
        )

        if requirements.camera, cameraSegments.isEmpty {
            throw ProgramVideoRendererError.missingCameraTrack
        }
        if requirements.screen, screenSegments.isEmpty {
            throw ProgramVideoRendererError.missingScreenTrack
        }

        let composition = AVMutableComposition()
        let cameraTrack = cameraSegments.isEmpty ? nil : composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let screenTrack = screenSegments.isEmpty ? nil : composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        let duration = await renderDuration(
            cameraSegments: cameraSegments,
            screenSegments: screenSegments,
            timelineDurationMilliseconds: timeline.durationMilliseconds
        )
        let exportTimeRange = exportTimeRange(selectedRange, within: duration)
        try await insertMicrophoneAudioIfAvailable(
            into: composition,
            session: session,
            duration: duration
        )
        let cameraNaturalSize = cameraSegments.first?.naturalSize ?? CGSize(width: 1920, height: 1080)
        let screenNaturalSize = screenSegments.first?.naturalSize ?? cameraNaturalSize
        if let cameraTrack {
            try await insertVideoTrack(
                cameraSegments,
                into: cameraTrack,
                duration: duration
            )
        }
        if let screenTrack {
            try await insertVideoTrack(
                screenSegments,
                into: screenTrack,
                duration: duration
            )
        }
        let renderSize = renderSize(
            settings: settings,
            primaryNaturalSize: primaryNaturalSize(
                cameraNaturalSize: cameraNaturalSize,
                screenNaturalSize: screenNaturalSize,
                requirements: requirements
            )
        )
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(settings.frameRate.rawValue))
        videoComposition.renderScale = 1
        videoComposition.customVideoCompositorClass = ProgramVideoCompositor.self
        videoComposition.instructions = try instructions(
	            for: timeline,
	            duration: duration,
	            cameraTrack: cameraTrack,
	            cameraNaturalSize: cameraNaturalSize,
	            screenTrack: screenTrack,
	            screenNaturalSize: screenNaturalSize,
	            screenContentCropRect: nil,
	            renderSize: renderSize,
	            presenterVideoEffects: session.manifest.presenterVideoEffects
	        )

        let destinationURL = outputURL ?? session.programOutputURL
        let temporaryOutputURL = temporaryExportURL(for: destinationURL)
        if fileManager.fileExists(atPath: temporaryOutputURL.path) {
            try fileManager.removeItem(at: temporaryOutputURL)
        }
        defer {
            if fileManager.fileExists(atPath: temporaryOutputURL.path) {
                try? fileManager.removeItem(at: temporaryOutputURL)
            }
        }

        let cancellationState = ProgramVideoRenderCancellationState()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await export(
                asset: composition,
                videoComposition: videoComposition,
                settings: settings,
                renderSize: renderSize,
                destinationURL: temporaryOutputURL,
                timeRange: exportTimeRange,
                cancellationState: cancellationState,
                progress: progress
            )
        } onCancel: {
            cancellationState.cancel()
        }
        try await Self.validatePlayableVideo(at: temporaryOutputURL, fileManager: fileManager)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: temporaryOutputURL, to: destinationURL)
        try await Self.validatePlayableVideo(at: destinationURL, fileManager: fileManager)
        progress?(
            ProgramVideoRenderProgress(
                fraction: 1,
                width: Int(renderSize.width),
                height: Int(renderSize.height),
                writtenBytes: fileSize(at: destinationURL),
                outputURL: destinationURL
            )
        )
        return destinationURL
    }

    private func temporaryExportURL(for destinationURL: URL) -> URL {
        let directory = destinationURL.deletingLastPathComponent()
        let baseName = destinationURL.deletingPathExtension().lastPathComponent
        return directory.appendingPathComponent(".\(baseName)-\(UUID().uuidString).rendering.mp4")
    }

    private func exportTimeRange(_ selectedRange: TimelineExportRange?, within duration: CMTime) -> CMTimeRange {
        guard let selectedRange else {
            return CMTimeRange(start: .zero, duration: duration)
        }
        let range = TimelineSelection(ranges: [selectedRange])
            .normalized(durationMilliseconds: max(1, Int(duration.seconds * 1000)))
            .ranges
            .first
        guard let range else {
            return CMTimeRange(start: .zero, duration: duration)
        }
        let start = CMTime(value: CMTimeValue(range.startMilliseconds), timescale: 1000)
        let end = CMTime(value: CMTimeValue(range.endMilliseconds), timescale: 1000)
        return CMTimeRange(start: start, end: end)
    }

    private func mediaRequirements(for timeline: RecordingTimeline) -> (camera: Bool, screen: Bool) {
        var requiresCamera = false
        var requiresScreen = false
        for segment in timeline.segments {
            for layer in segment.scene.layers {
                switch layer.source {
                case .presenterCamera:
                    requiresCamera = true
                case .slidesScreen:
                    requiresScreen = true
                }
            }
        }
        return (requiresCamera, requiresScreen)
    }

    private func videoSourceSegments(
        urls: [URL],
        isRequired: Bool,
        missingError: ProgramVideoRendererError
    ) async throws -> [VideoSourceSegment] {
        var segments: [VideoSourceSegment] = []
        for url in urls {
            guard fileManager.fileExists(atPath: url.path) else {
                continue
            }
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                continue
            }
            let duration = (try? await asset.load(.duration)) ?? .invalid
            guard duration.isValid, duration.seconds > 0 else {
                continue
            }
            let naturalSize = (try? await track.load(.naturalSize)) ?? CGSize(width: 1920, height: 1080)
            segments.append(
                VideoSourceSegment(
                    asset: asset,
                    track: track,
                    duration: duration,
                    naturalSize: naturalSize
                )
            )
        }
        if segments.isEmpty, isRequired {
            throw missingError
        }
        return segments
    }

    private func renderSize(
        settings: RecordingExportSettings,
        primaryNaturalSize: CGSize
    ) -> CGSize {
        if let pixelSize = settings.effectivePixelSize {
            return CGSize(width: pixelSize.width, height: pixelSize.height)
        }

        let width = max(1, Int(abs(primaryNaturalSize.width)))
        let height = max(1, Int(abs(primaryNaturalSize.height)))
        return CGSize(width: width, height: height)
    }

    private func primaryNaturalSize(
        cameraNaturalSize: CGSize,
        screenNaturalSize: CGSize,
        requirements: (camera: Bool, screen: Bool)
    ) -> CGSize {
        if requirements.screen {
            return screenNaturalSize
        }
        return cameraNaturalSize
    }

    private func videoOutputSettings(
        settings: RecordingExportSettings,
        renderSize: CGSize
    ) -> [String: Any] {
        [
            AVVideoCodecKey: videoCodecType(for: settings),
            AVVideoWidthKey: Int(renderSize.width),
            AVVideoHeightKey: Int(renderSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: settings.bitrateBitsPerSecond,
                AVVideoExpectedSourceFrameRateKey: settings.frameRate.rawValue,
                AVVideoMaxKeyFrameIntervalKey: settings.frameRate.rawValue * 2,
                AVVideoAllowFrameReorderingKey: false
            ]
        ]
    }

    private func audioOutputSettings(settings: RecordingExportSettings) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 48_000,
            AVEncoderBitRateKey: settings.audioBitrateBitsPerSecond
        ]
    }

    private func videoCodecType(for settings: RecordingExportSettings) -> AVVideoCodecType {
        switch settings.codec {
        case .h264:
            return .h264
        case .hevc:
            return .hevc
        }
    }

    private func insertMicrophoneAudioIfAvailable(
        into composition: AVMutableComposition,
        session: RecordingSessionRecord,
        duration: CMTime
    ) async throws {
        let segments = try await audioSourceSegments(urls: session.microphoneAudioSegmentURLs)
        guard !segments.isEmpty,
              let compositionTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            return
        }
        try insertAudioSegments(segments, into: compositionTrack, duration: duration)
    }

    private func audioSourceSegments(urls: [URL]) async throws -> [AudioSourceSegment] {
        var segments: [AudioSourceSegment] = []
        for url in urls {
            guard fileManager.fileExists(atPath: url.path) else {
                continue
            }
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
                continue
            }
            let duration = (try? await asset.load(.duration)) ?? .invalid
            guard duration.isValid, duration.seconds > 0 else {
                continue
            }
            segments.append(AudioSourceSegment(asset: asset, track: track, duration: duration))
        }
        return segments
    }

    private func renderDuration(
        cameraSegments: [VideoSourceSegment],
        screenSegments: [VideoSourceSegment],
        timelineDurationMilliseconds: Int
    ) async -> CMTime {
        if timelineDurationMilliseconds > 0 {
            return CMTime(value: CMTimeValue(timelineDurationMilliseconds), timescale: 1_000)
        }

        let cameraDuration = totalDuration(of: cameraSegments)
        let screenDuration = totalDuration(of: screenSegments)
        var candidates: [CMTime] = []
        if cameraDuration.isValid, cameraDuration.seconds > 0 {
            candidates.append(cameraDuration)
        }
        if screenDuration.isValid, screenDuration.seconds > 0 {
            candidates.append(screenDuration)
        }
        if let longestDuration = candidates.max(by: { $0.seconds < $1.seconds }) {
            return longestDuration
        }
        return CMTime(seconds: 1, preferredTimescale: 600)
    }

    private func insertVideoTrack(
        _ segments: [VideoSourceSegment],
        into compositionTrack: AVMutableCompositionTrack,
        duration: CMTime
    ) async throws {
        var cursor = CMTime.zero
        for segment in segments {
            guard cursor < duration else {
                break
            }
            let availableDuration = minValidDuration(segment.duration, duration - cursor)
            guard availableDuration.seconds > 0 else {
                continue
            }
            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: availableDuration),
                of: segment.track,
                at: cursor
            )
            cursor = cursor + availableDuration
        }

        if duration > cursor {
            compositionTrack.insertEmptyTimeRange(
                CMTimeRange(start: cursor, duration: duration - cursor)
            )
        }
    }

    private func insertAudioSegments(
        _ segments: [AudioSourceSegment],
        into compositionTrack: AVMutableCompositionTrack,
        duration: CMTime
    ) throws {
        var cursor = CMTime.zero
        for segment in segments {
            guard cursor < duration else {
                break
            }
            let availableDuration = minValidDuration(segment.duration, duration - cursor)
            guard availableDuration.seconds > 0 else {
                continue
            }
            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: availableDuration),
                of: segment.track,
                at: cursor
            )
            cursor = cursor + availableDuration
        }
    }

    private func totalDuration(of segments: [VideoSourceSegment]) -> CMTime {
        segments.reduce(CMTime.zero) { partialResult, segment in
            partialResult + segment.duration
        }
    }

    private func minValidDuration(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
        let lhsValid = lhs.isValid && lhs.seconds.isFinite && lhs.seconds > 0
        let rhsValid = rhs.isValid && rhs.seconds.isFinite && rhs.seconds > 0
        switch (lhsValid, rhsValid) {
        case (true, true):
            return lhs < rhs ? lhs : rhs
        case (true, false):
            return lhs
        case (false, true):
            return rhs
        case (false, false):
            return .zero
        }
    }

    private func instructions(
        for timeline: RecordingTimeline,
        duration: CMTime,
        cameraTrack: AVCompositionTrack?,
        cameraNaturalSize: CGSize,
        screenTrack: AVCompositionTrack?,
        screenNaturalSize: CGSize,
        screenContentCropRect: CGRect?,
        renderSize: CGSize,
        presenterVideoEffects: PresenterVideoEffects
    ) throws -> [AVVideoCompositionInstructionProtocol] {
        var instructions: [AVVideoCompositionInstructionProtocol] = []

        for segment in timeline.segments {
            let start = boundedTimelineTime(
                milliseconds: segment.startMilliseconds,
                duration: duration
            )
            let end = boundedTimelineTime(
                milliseconds: segment.endMilliseconds,
                duration: duration
            )
            let segmentRange = CMTimeRange(
                start: start,
                end: end
            )
            guard segmentRange.duration.seconds > 0 else {
                continue
            }

            let instruction = try ProgramVideoCompositionInstruction(
                timeRange: segmentRange,
                canvasRect: canvasRect(
                    for: segment.scene.canvasPixelSize,
                    renderSize: renderSize
                ),
                layers: renderLayers(
                    for: segment.scene,
                    cameraTrack: cameraTrack,
                    cameraNaturalSize: cameraNaturalSize,
                    screenTrack: screenTrack,
                    screenNaturalSize: screenNaturalSize,
                    screenContentCropRect: screenContentCropRect,
                    presenterVideoEffects: presenterVideoEffects
                )
            )
            instructions.append(instruction)
        }

        return instructions
    }

    private func canvasRect(
        for canvasPixelSize: RecordingExportPixelSize?,
        renderSize: CGSize
    ) -> CGRect {
        guard let canvasPixelSize else {
            return CGRect(origin: .zero, size: renderSize)
        }
        return ScreenArchiveRecorder.maxIntegralAspectFitRect(
            sourceSize: CGSize(width: canvasPixelSize.width, height: canvasPixelSize.height),
            targetSize: renderSize
        )
    }

    private func boundedTimelineTime(milliseconds: Int, duration: CMTime) -> CMTime {
        guard milliseconds > 0 else {
            return .zero
        }
        let time = CMTime(value: CMTimeValue(milliseconds), timescale: 1_000)
        return time > duration ? duration : time
    }

    private func renderLayers(
        for scene: ProgramScene,
        cameraTrack: AVCompositionTrack?,
        cameraNaturalSize: CGSize,
        screenTrack: AVCompositionTrack?,
        screenNaturalSize: CGSize,
        screenContentCropRect: CGRect?,
        presenterVideoEffects: PresenterVideoEffects
    ) throws -> [ProgramVideoRenderLayer] {
        switch scene.view {
        case .speakerFullBody:
            guard let cameraTrack else {
                throw ProgramVideoRendererError.missingCameraTrack
            }
            return [
                ProgramVideoRenderLayer(
                    trackID: cameraTrack.trackID,
                    naturalSize: cameraNaturalSize,
                    sourceCropRect: nil,
                    placement: .fullCanvas,
                    fillMode: .fit,
                    trimsBlackMatte: true,
                    sourceCrop: nil,
                    presenterVideoEffects: presenterVideoEffects
                )
            ]
        case .speakerCloseUp:
            guard let cameraTrack else {
                throw ProgramVideoRendererError.missingCameraTrack
            }
            return [
                ProgramVideoRenderLayer(
                    trackID: cameraTrack.trackID,
                    naturalSize: cameraNaturalSize,
                    sourceCropRect: nil,
                    placement: .fullCanvas,
                    fillMode: .closeUp,
                    trimsBlackMatte: true,
                    sourceCrop: nil,
                    presenterVideoEffects: presenterVideoEffects
                )
            ]
        case .slidesFullScreen:
            guard let screenTrack else {
                throw ProgramVideoRendererError.missingScreenTrack
            }
            return [
                ProgramVideoRenderLayer(
                    trackID: screenTrack.trackID,
                    naturalSize: screenContentCropRect?.size ?? screenNaturalSize,
                    sourceCropRect: screenContentCropRect,
                    placement: .fullCanvas,
                    fillMode: .fit,
                    trimsBlackMatte: false,
                    sourceCrop: nil,
                    presenterVideoEffects: .default
                )
            ]
        case .slidesWithSpeakerPictureInPicture:
            guard let screenTrack else {
                throw ProgramVideoRendererError.missingScreenTrack
            }
            guard let cameraTrack else {
                throw ProgramVideoRendererError.missingCameraTrack
            }
            let speakerLayer = scene.speakerLayer ?? ProgramLayer(
                source: .presenterCamera,
                placement: .pictureInPicture(corner: .bottomRight, size: .medium),
                speakerShot: .closeUp
            )
            return [
                ProgramVideoRenderLayer(
                    trackID: cameraTrack.trackID,
                    naturalSize: cameraNaturalSize,
                    sourceCropRect: nil,
                    placement: speakerLayer.placement,
                    fillMode: .fill,
                    trimsBlackMatte: true,
                    sourceCrop: speakerLayer.sourceCrop,
                    presenterVideoEffects: presenterVideoEffects
                ),
                ProgramVideoRenderLayer(
                    trackID: screenTrack.trackID,
                    naturalSize: screenContentCropRect?.size ?? screenNaturalSize,
                    sourceCropRect: screenContentCropRect,
                    placement: .fullCanvas,
                    fillMode: .fit,
                    trimsBlackMatte: false,
                    sourceCrop: nil,
                    presenterVideoEffects: .default
                )
            ]
        case .speakerWithSlidesPictureInPicture:
            guard let cameraTrack else {
                throw ProgramVideoRendererError.missingCameraTrack
            }
            guard let screenTrack else {
                throw ProgramVideoRendererError.missingScreenTrack
            }
            return [
                ProgramVideoRenderLayer(
                    trackID: screenTrack.trackID,
                    naturalSize: screenContentCropRect?.size ?? screenNaturalSize,
                    sourceCropRect: screenContentCropRect,
                    placement: scene.layers.first(where: { $0.source == .slidesScreen })?.placement ?? .pictureInPicture(corner: .topRight, size: .medium),
                    fillMode: .fit,
                    trimsBlackMatte: false,
                    sourceCrop: scene.layers.first(where: { $0.source == .slidesScreen })?.sourceCrop,
                    presenterVideoEffects: .default
                ),
                ProgramVideoRenderLayer(
                    trackID: cameraTrack.trackID,
                    naturalSize: cameraNaturalSize,
                    sourceCropRect: nil,
                    placement: .fullCanvas,
                    fillMode: .fit,
                    trimsBlackMatte: true,
                    sourceCrop: nil,
                    presenterVideoEffects: presenterVideoEffects
                )
            ]
        case .sideBySide:
            guard let screenTrack else {
                throw ProgramVideoRendererError.missingScreenTrack
            }
            guard let cameraTrack else {
                throw ProgramVideoRendererError.missingCameraTrack
            }
            let screenLayer = scene.layers.first(where: { $0.source == .slidesScreen })
            let cameraLayer = scene.layers.first(where: { $0.source == .presenterCamera })
            return [
                ProgramVideoRenderLayer(
                    trackID: cameraTrack.trackID,
                    naturalSize: cameraNaturalSize,
                    sourceCropRect: nil,
                    placement: cameraLayer?.placement ?? .rightHalf,
                    fillMode: .fill,
                    trimsBlackMatte: true,
                    sourceCrop: cameraLayer?.sourceCrop,
                    presenterVideoEffects: presenterVideoEffects
                ),
                ProgramVideoRenderLayer(
                    trackID: screenTrack.trackID,
                    naturalSize: screenContentCropRect?.size ?? screenNaturalSize,
                    sourceCropRect: screenContentCropRect,
                    placement: screenLayer?.placement ?? .leftHalf,
                    fillMode: .fill,
                    trimsBlackMatte: false,
                    sourceCrop: screenLayer?.sourceCrop,
                    presenterVideoEffects: .default
                )
            ]
        case .topBottom:
            guard let screenTrack else {
                throw ProgramVideoRendererError.missingScreenTrack
            }
            guard let cameraTrack else {
                throw ProgramVideoRendererError.missingCameraTrack
            }
            let screenLayer = scene.layers.first(where: { $0.source == .slidesScreen })
            let cameraLayer = scene.layers.first(where: { $0.source == .presenterCamera })
            return [
                ProgramVideoRenderLayer(
                    trackID: cameraTrack.trackID,
                    naturalSize: cameraNaturalSize,
                    sourceCropRect: nil,
                    placement: cameraLayer?.placement ?? .bottomHalf,
                    fillMode: .fill,
                    trimsBlackMatte: true,
                    sourceCrop: cameraLayer?.sourceCrop,
                    presenterVideoEffects: presenterVideoEffects
                ),
                ProgramVideoRenderLayer(
                    trackID: screenTrack.trackID,
                    naturalSize: screenContentCropRect?.size ?? screenNaturalSize,
                    sourceCropRect: screenContentCropRect,
                    placement: screenLayer?.placement ?? .topHalf,
                    fillMode: .fill,
                    trimsBlackMatte: false,
                    sourceCrop: screenLayer?.sourceCrop,
                    presenterVideoEffects: .default
                )
            ]
        }
    }

    private func export(
        asset: AVAsset,
        videoComposition: AVVideoComposition,
        settings: RecordingExportSettings,
        renderSize: CGSize,
        destinationURL: URL,
        timeRange: CMTimeRange,
        cancellationState: ProgramVideoRenderCancellationState,
        progress: (@Sendable (ProgramVideoRenderProgress) -> Void)?
    ) async throws {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = timeRange
        let writer = try AVAssetWriter(outputURL: destinationURL, fileType: .mp4)
        let progressEmitter = ProgramVideoRenderProgressEmitter(
            duration: timeRange.duration,
            renderSize: renderSize,
            destinationURL: destinationURL,
            fileManager: fileManager,
            progress: progress
        )
        progressEmitter.emit(fraction: 0, force: true)

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else {
            throw ProgramVideoRendererError.missingScreenTrack
        }

        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: videoTracks,
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        videoOutput.videoComposition = videoComposition
        videoOutput.alwaysCopiesSampleData = false

        guard reader.canAdd(videoOutput) else {
            throw ProgramVideoRendererError.exportFailed("无法读取合成视频轨")
        }
        reader.add(videoOutput)

        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoOutputSettings(settings: settings, renderSize: renderSize)
        )
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else {
            throw ProgramVideoRendererError.exportFailed("无法写入所选视频编码参数")
        }
        writer.add(videoInput)

        let audioPair = try await makeAudioReaderOutputAndWriterInput(
            asset: asset,
            settings: settings,
            reader: reader,
            writer: writer
        )

        let exportBox = ReaderWriterExportBox(
            reader: reader,
            writer: writer,
            videoOutput: videoOutput,
            videoInput: videoInput,
            audioOutput: audioPair?.output,
            audioInput: audioPair?.input
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            guard exportBox.writer.startWriting() else {
                let message = exportBox.writer.error?.localizedDescription ?? "writer 启动失败"
                continuation.resume(throwing: ProgramVideoRendererError.exportFailed(message))
                return
            }
            guard exportBox.reader.startReading() else {
                exportBox.writer.cancelWriting()
                let message = exportBox.reader.error?.localizedDescription ?? "reader 启动失败"
                continuation.resume(throwing: ProgramVideoRendererError.exportFailed(message))
                return
            }

            exportBox.writer.startSession(atSourceTime: .zero)
            let group = DispatchGroup()
            let queue = DispatchQueue(label: "com.wondershow.program-video-renderer.export")

            group.enter()
            let videoFinishState = PumpFinishState()
            let videoRetimer = SampleRetimer(frameRate: settings.frameRate.rawValue)
            exportBox.videoInput.requestMediaDataWhenReady(on: queue) {
                while exportBox.videoInput.isReadyForMoreMediaData, videoFinishState.isActive {
                    if cancellationState.isCancelled {
                        videoFinishState.finish {
                            exportBox.videoInput.markAsFinished()
                            exportBox.reader.cancelReading()
                            exportBox.writer.cancelWriting()
                            group.leave()
                        }
                        break
                    }
                    if let sampleBuffer = exportBox.videoOutput.copyNextSampleBuffer() {
                        let timedSampleBuffer = videoRetimer.retimed(sampleBuffer) ?? sampleBuffer
                        if !exportBox.videoInput.append(timedSampleBuffer) {
                            videoFinishState.finish {
                                exportBox.videoInput.markAsFinished()
                                exportBox.reader.cancelReading()
                                group.leave()
                            }
                            break
                        }
                        progressEmitter.emit(sampleBuffer: timedSampleBuffer)
                    } else {
                        videoFinishState.finish {
                            exportBox.videoInput.markAsFinished()
                            group.leave()
                        }
                        break
                    }
                }
            }

            if exportBox.audioOutput != nil, exportBox.audioInput != nil {
                group.enter()
                let audioFinishState = PumpFinishState()
                exportBox.audioInput?.requestMediaDataWhenReady(on: queue) {
                    guard let audioOutput = exportBox.audioOutput,
                          let audioInput = exportBox.audioInput else {
                        audioFinishState.finish {
                            group.leave()
                        }
                        return
                    }
                    while audioInput.isReadyForMoreMediaData, audioFinishState.isActive {
                        if cancellationState.isCancelled {
                            audioFinishState.finish {
                                audioInput.markAsFinished()
                                exportBox.reader.cancelReading()
                                exportBox.writer.cancelWriting()
                                group.leave()
                            }
                            break
                        }
                        if let sampleBuffer = audioOutput.copyNextSampleBuffer() {
                            if !audioInput.append(sampleBuffer) {
                                audioFinishState.finish {
                                    audioInput.markAsFinished()
                                    exportBox.reader.cancelReading()
                                    group.leave()
                                }
                                break
                            }
                        } else {
                            audioFinishState.finish {
                                audioInput.markAsFinished()
                                group.leave()
                            }
                            break
                        }
                    }
                }
            }

            group.notify(queue: queue) {
                if cancellationState.isCancelled {
                    exportBox.reader.cancelReading()
                    exportBox.writer.cancelWriting()
                    continuation.resume(throwing: ProgramVideoRendererError.cancelled)
                    return
                }
                if exportBox.reader.status == .failed || exportBox.reader.status == .cancelled {
                    exportBox.writer.cancelWriting()
                    if cancellationState.isCancelled {
                        continuation.resume(throwing: ProgramVideoRendererError.cancelled)
                    } else {
                        let message = exportBox.reader.error?.localizedDescription ?? "reader 状态异常"
                        continuation.resume(throwing: ProgramVideoRendererError.exportFailed(message))
                    }
                    return
                }

                progressEmitter.emit(fraction: 0.98, force: true)
                exportBox.writer.finishWriting {
                    switch exportBox.writer.status {
                    case .completed:
                        progressEmitter.emit(fraction: 1, force: true)
                        continuation.resume()
                    case .failed, .cancelled:
                        let message = exportBox.writer.error?.localizedDescription ?? "writer 状态异常"
                        continuation.resume(throwing: ProgramVideoRendererError.exportFailed(message))
                    default:
                        continuation.resume(throwing: ProgramVideoRendererError.exportFailed("writer 未正常完成"))
                    }
                }
            }
        }
    }

    private func fileSize(at url: URL) -> Int64 {
        let size = try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        return size?.int64Value ?? 0
    }

    private func makeAudioReaderOutputAndWriterInput(
        asset: AVAsset,
        settings: RecordingExportSettings,
        reader: AVAssetReader,
        writer: AVAssetWriter
    ) async throws -> (output: AVAssetReaderTrackOutput, input: AVAssetWriterInput)? {
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            return nil
        }

        let audioOutput = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsNonInterleaved: false
            ]
        )
        audioOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(audioOutput) else {
            return nil
        }
        reader.add(audioOutput)

        let audioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: audioOutputSettings(settings: settings)
        )
        audioInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(audioInput) else {
            return nil
        }
        writer.add(audioInput)
        return (audioOutput, audioInput)
    }
}

private final class PumpFinishState: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !finished
    }

    func finish(_ body: () -> Void) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()
        body()
    }
}

private final class SampleRetimer: @unchecked Sendable {
    private let frameDuration: CMTime
    private var frameIndex: CMTimeValue = 0

    init(frameRate: Int) {
        frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, frameRate)))
    }

    func retimed(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: frameDuration,
            presentationTimeStamp: CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex)),
            decodeTimeStamp: .invalid
        )
        frameIndex += 1

        var output: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &output
        )
        guard status == noErr else {
            return nil
        }
        return output
    }
}

private final class ReaderWriterExportBox: @unchecked Sendable {
    let reader: AVAssetReader
    let writer: AVAssetWriter
    let videoOutput: AVAssetReaderVideoCompositionOutput
    let videoInput: AVAssetWriterInput
    let audioOutput: AVAssetReaderTrackOutput?
    let audioInput: AVAssetWriterInput?

    init(
        reader: AVAssetReader,
        writer: AVAssetWriter,
        videoOutput: AVAssetReaderVideoCompositionOutput,
        videoInput: AVAssetWriterInput,
        audioOutput: AVAssetReaderTrackOutput?,
        audioInput: AVAssetWriterInput?
    ) {
        self.reader = reader
        self.writer = writer
        self.videoOutput = videoOutput
        self.videoInput = videoInput
        self.audioOutput = audioOutput
        self.audioInput = audioInput
    }
}

private final class ProgramVideoRenderCancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

private final class ProgramVideoRenderProgressEmitter: @unchecked Sendable {
    private let durationSeconds: Double
    private let width: Int
    private let height: Int
    private let destinationURL: URL
    private let fileManager: FileManager
    private let progress: (@Sendable (ProgramVideoRenderProgress) -> Void)?
    private let lock = NSLock()
    private var lastFraction: Double = -1
    private var lastEmitDate = Date.distantPast

    init(
        duration: CMTime,
        renderSize: CGSize,
        destinationURL: URL,
        fileManager: FileManager,
        progress: (@Sendable (ProgramVideoRenderProgress) -> Void)?
    ) {
        durationSeconds = duration.isValid && duration.seconds.isFinite ? max(0.001, duration.seconds) : 1
        width = Int(renderSize.width)
        height = Int(renderSize.height)
        self.destinationURL = destinationURL
        self.fileManager = fileManager
        self.progress = progress
    }

    func emit(sampleBuffer: CMSampleBuffer) {
        let seconds = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard seconds.isFinite else {
            return
        }
        emit(fraction: min(max(seconds / durationSeconds, 0), 0.98), force: false)
    }

    func emit(fraction: Double, force: Bool) {
        guard let progress else {
            return
        }

        let boundedFraction = min(max(fraction, 0), 1)
        let now = Date()
        lock.lock()
        let shouldEmit = force
            || boundedFraction - lastFraction >= 0.01
            || now.timeIntervalSince(lastEmitDate) >= 0.20
        if shouldEmit {
            lastFraction = boundedFraction
            lastEmitDate = now
        }
        lock.unlock()

        guard shouldEmit else {
            return
        }

        let size = (try? fileManager.attributesOfItem(atPath: destinationURL.path)[.size] as? NSNumber)?
            .int64Value ?? 0
        progress(
            ProgramVideoRenderProgress(
                fraction: boundedFraction,
                width: width,
                height: height,
                writtenBytes: size,
                outputURL: destinationURL
            )
        )
    }
}

private enum ProgramVideoFillMode: Hashable, Sendable {
    case fit
    case fill
    case closeUp
}

private struct ProgramVideoRenderLayer: Hashable, Sendable {
    let trackID: CMPersistentTrackID
    let naturalSize: CGSize
    let sourceCropRect: CGRect?
    let placement: ProgramLayerPlacement
    let fillMode: ProgramVideoFillMode
    let trimsBlackMatte: Bool
    let sourceCrop: ProgramLayerSourceCrop?
    let presenterVideoEffects: PresenterVideoEffects
}

private enum ProgramBlackMatteCropDetector {
    static func contentRect(in image: CGImage) -> CGRect? {
        let width = image.width
        let height = image.height
        guard width >= 320, height >= 240 else {
            return nil
        }
        let sampleStep = max(2, min(width, height) / 240)
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        var contentSamples = 0

        guard let bytes = rgbaBytes(from: image) else {
            return nil
        }
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel

        for y in stride(from: 0, to: height, by: sampleStep) {
            for x in stride(from: 0, to: width, by: sampleStep) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let red = Int(bytes[offset])
                let green = Int(bytes[offset + 1])
                let blue = Int(bytes[offset + 2])
                if red + green + blue > 42 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                    contentSamples += 1
                }
            }
        }

        guard contentSamples > 16, maxX > minX, maxY > minY else {
            return nil
        }
        let expansion = sampleStep * 2
        let rect = CGRect(
            x: max(0, minX - expansion),
            y: max(0, minY - expansion),
            width: min(width - 1, maxX + expansion) - max(0, minX - expansion) + 1,
            height: min(height - 1, maxY + expansion) - max(0, minY - expansion) + 1
        ).integral
        let imageArea = CGFloat(width * height)
        let rectArea = rect.width * rect.height
        guard rectArea / imageArea >= 0.10, rectArea / imageArea <= 0.92 else {
            return nil
        }
        guard nonBlackSampleRatio(
            bytes: bytes,
            imageWidth: width,
            imageHeight: height,
            rect: rect,
            sampleStep: sampleStep
        ) >= 0.18 else {
            return nil
        }
        guard rect.minX > 8 || rect.minY > 8 || rect.maxX < CGFloat(width - 8) || rect.maxY < CGFloat(height - 8) else {
            return nil
        }
        return rect
    }

    private static func nonBlackSampleRatio(
        bytes: [UInt8],
        imageWidth: Int,
        imageHeight: Int,
        rect: CGRect,
        sampleStep: Int
    ) -> CGFloat {
        let minX = max(0, Int(rect.minX))
        let maxX = min(imageWidth - 1, Int(rect.maxX))
        let minY = max(0, Int(rect.minY))
        let maxY = min(imageHeight - 1, Int(rect.maxY))
        guard minX < maxX, minY < maxY else {
            return 0
        }
        let bytesPerPixel = 4
        let bytesPerRow = imageWidth * bytesPerPixel
        var totalSamples = 0
        var nonBlackSamples = 0
        for y in stride(from: minY, through: maxY, by: sampleStep) {
            for x in stride(from: minX, through: maxX, by: sampleStep) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let red = Int(bytes[offset])
                let green = Int(bytes[offset + 1])
                let blue = Int(bytes[offset + 2])
                totalSamples += 1
                if red + green + blue > 42 {
                    nonBlackSamples += 1
                }
            }
        }
        guard totalSamples > 0 else {
            return 0
        }
        return CGFloat(nonBlackSamples) / CGFloat(totalSamples)
    }

    private static func rgbaBytes(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }
}

private final class ProgramVideoCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let canvasRect: CGRect
    let layers: [ProgramVideoRenderLayer]

    init(timeRange: CMTimeRange, canvasRect: CGRect, layers: [ProgramVideoRenderLayer]) {
        self.timeRange = timeRange
        self.canvasRect = canvasRect
        self.layers = layers
    }

    var requiredSourceTrackIDs: [NSValue]? {
        layers.map { NSNumber(value: $0.trackID) as NSValue }
    }
}

private final class ProgramVideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let context = CIContext()
    private let presenterEnhancementPipeline = PresenterEnhancementPipeline()
    private var renderSize = CGSize(width: 1920, height: 1080)

    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderSize = newRenderContext.size
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        autoreleasepool {
            guard let instruction = request.videoCompositionInstruction as? ProgramVideoCompositionInstruction else {
                request.finish(with: ProgramVideoRendererError.exportFailed("合成指令类型不匹配"))
                return
            }
            guard let outputBuffer = request.renderContext.newPixelBuffer() else {
                request.finish(with: ProgramVideoRendererError.exportFailed("无法创建合成帧"))
                return
            }

            let renderRect = CGRect(origin: .zero, size: renderSize)
            var composedImage = CIImage(color: .black).cropped(to: renderRect)

            for layer in instruction.layers.reversed() {
                guard let sourceBuffer = request.sourceFrame(byTrackID: layer.trackID) else {
                    continue
                }
                let sourceImage = Self.sourceImage(
                    from: sourceBuffer,
                    cropRect: layer.sourceCropRect,
                    trimsBlackMatte: layer.trimsBlackMatte
                )
                let geometry = ProgramLayerGeometry(
                    naturalSize: sourceImage.extent.size,
                    placement: layer.placement,
                    renderSize: renderSize,
                    canvasRect: instruction.canvasRect,
                    fillMode: layer.fillMode,
                    sourceCrop: layer.sourceCrop
                )
                let fittedImage = Self.scaledImage(
                    sourceImage,
                    scale: geometry.scale,
                    translation: geometry.translation
                )
                let effectedImage = presenterEnhancementPipeline.apply(
                    to: fittedImage,
                    effects: layer.presenterVideoEffects,
                    targetRect: geometry.rect,
                    fallbackPortrait: true
                )
                let clippedImage = effectedImage
                    .cropped(to: geometry.rect)
                    .applyingFilter("CIBlendWithAlphaMask", parameters: [
                        kCIInputBackgroundImageKey: composedImage,
                        kCIInputMaskImageKey: geometry.maskImage
                    ])
                composedImage = clippedImage.cropped(to: renderRect)
            }

            context.render(composedImage, to: outputBuffer)
            request.finish(withComposedVideoFrame: outputBuffer)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {}

    private static func sourceImage(
        from sourceBuffer: CVPixelBuffer,
        cropRect: CGRect?,
        trimsBlackMatte: Bool
    ) -> CIImage {
        let image = CIImage(cvPixelBuffer: sourceBuffer)
        let resolvedCropRect = cropRect ?? (trimsBlackMatte ? CameraFrameMatteDetector.contentRect(in: sourceBuffer) : nil)
        guard let resolvedCropRect else {
            return image
        }
        let safeRect = resolvedCropRect
            .standardized
            .intersection(image.extent)
            .integral
        guard safeRect.width > 1, safeRect.height > 1 else {
            return image
        }
        return image
            .cropped(to: safeRect)
            .transformed(by: CGAffineTransform(translationX: -safeRect.minX, y: -safeRect.minY))
    }

    private static func scaledImage(
        _ image: CIImage,
        scale: CGFloat,
        translation: CGSize
    ) -> CIImage {
        image
            .applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: 1
            ])
            .transformed(by: CGAffineTransform(translationX: translation.width, y: translation.height))
    }
}

private struct ProgramLayerGeometry {
    let rect: CGRect
    let scale: CGFloat
    let translation: CGSize
    let maskImage: CIImage

    init(
        naturalSize: CGSize,
        placement: ProgramLayerPlacement,
        renderSize: CGSize,
        canvasRect: CGRect,
        fillMode: ProgramVideoFillMode,
        sourceCrop: ProgramLayerSourceCrop? = nil
    ) {
        let sourceSize = CGSize(
            width: max(1, abs(naturalSize.width)),
            height: max(1, abs(naturalSize.height))
        )
        let rect = Self.targetRect(
            placement: placement,
            sourceSize: sourceSize,
            renderSize: renderSize,
            canvasRect: canvasRect
        )
        let scale: CGFloat
        switch fillMode {
        case .fit:
            scale = min(rect.width / sourceSize.width, rect.height / sourceSize.height)
        case .fill:
            scale = max(rect.width / sourceSize.width, rect.height / sourceSize.height)
        case .closeUp:
            scale = max(rect.width / sourceSize.width, rect.height / sourceSize.height) * 1.35
        }
        let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let sourceOffset = Self.sourceOffset(
            sourceCrop: sourceCrop,
            scaledSize: scaledSize,
            targetRect: rect
        )
        self.rect = rect
        self.scale = scale
        self.translation = CGSize(
            width: rect.midX - scaledSize.width / 2 + sourceOffset.width,
            height: rect.midY - scaledSize.height / 2 + sourceOffset.height
        )
        self.maskImage = Self.maskImage(for: placement, rect: rect)
    }

    private static func sourceOffset(
        sourceCrop: ProgramLayerSourceCrop?,
        scaledSize: CGSize,
        targetRect: CGRect
    ) -> CGSize {
        guard let sourceCrop else {
            return .zero
        }
        let overflowX = max(0, scaledSize.width - targetRect.width)
        let overflowY = max(0, scaledSize.height - targetRect.height)
        return CGSize(
            width: CGFloat(sourceCrop.offsetX) * overflowX / 2,
            height: CGFloat(sourceCrop.offsetY) * overflowY / 2
        )
    }

    private static func targetRect(
        placement: ProgramLayerPlacement,
        sourceSize: CGSize,
        renderSize: CGSize,
        canvasRect: CGRect
    ) -> CGRect {
        switch placement {
        case .fullCanvas:
            return canvasRect
        case .pictureInPicture(let corner, let size):
            let widthFraction: CGFloat
            switch size {
            case .small:
                widthFraction = 0.22
            case .medium:
                widthFraction = 0.28
            case .large:
                widthFraction = 0.34
            }
            let targetWidth = canvasRect.width * widthFraction
            let targetHeight = sourceSize.height * (targetWidth / sourceSize.width)
            let margin: CGFloat = 36
            let x: CGFloat
            let y: CGFloat
            switch corner {
            case .topLeft:
                x = canvasRect.minX + margin
                y = canvasRect.maxY - targetHeight - margin
            case .topRight:
                x = canvasRect.maxX - targetWidth - margin
                y = canvasRect.maxY - targetHeight - margin
            case .bottomLeft:
                x = canvasRect.minX + margin
                y = canvasRect.minY + margin
            case .bottomRight:
                x = canvasRect.maxX - targetWidth - margin
                y = canvasRect.minY + margin
            }
            return CGRect(x: x, y: y, width: targetWidth, height: targetHeight)
        case .customPictureInPicture(let geometry):
            let targetWidth = max(1, canvasRect.width * CGFloat(geometry.width))
            let targetHeight = max(1, canvasRect.height * CGFloat(geometry.height))
            let centerX = canvasRect.minX + canvasRect.width * CGFloat(geometry.centerX)
            let centerY = canvasRect.minY + canvasRect.height * (1 - CGFloat(geometry.centerY))
            return CGRect(
                x: centerX - targetWidth / 2,
                y: centerY - targetHeight / 2,
                width: targetWidth,
                height: targetHeight
            )
        case .leftHalf:
            return CGRect(x: canvasRect.minX, y: canvasRect.minY, width: canvasRect.width / 2, height: canvasRect.height)
        case .rightHalf:
            return CGRect(x: canvasRect.midX, y: canvasRect.minY, width: canvasRect.width / 2, height: canvasRect.height)
        case .topHalf:
            return CGRect(x: canvasRect.minX, y: canvasRect.midY, width: canvasRect.width, height: canvasRect.height / 2)
        case .bottomHalf:
            return CGRect(x: canvasRect.minX, y: canvasRect.minY, width: canvasRect.width, height: canvasRect.height / 2)
        }
    }

    private static func maskImage(for placement: ProgramLayerPlacement, rect: CGRect) -> CIImage {
        let shape: ProgramPictureInPictureShape
        switch placement {
        case .customPictureInPicture(let geometry):
            shape = geometry.shape
        case .pictureInPicture:
            shape = .roundedRectangle
        case .fullCanvas, .leftHalf, .rightHalf, .topHalf, .bottomHalf:
            return CIImage(color: .white).cropped(to: rect)
        }

        switch shape {
        case .square:
            return CIImage(color: .white).cropped(to: rect)
        case .circle:
            let radius = min(rect.width, rect.height) / 2
            return CIImage(color: .white)
                .cropped(to: rect)
                .applyingFilter("CIRadialGradient", parameters: [
                    "inputCenter": CIVector(x: rect.midX, y: rect.midY),
                    "inputRadius0": radius - 1,
                    "inputRadius1": radius,
                    "inputColor0": CIColor.white,
                    "inputColor1": CIColor.clear
                ])
                .cropped(to: rect)
        case .roundedRectangle:
            return roundedRectangleMask(rect: rect, radius: min(22, min(rect.width, rect.height) * 0.14))
        }
    }

    private static func roundedRectangleMask(rect: CGRect, radius: CGFloat) -> CIImage {
        let base = CIImage(color: .white).cropped(to: rect.insetBy(dx: radius, dy: 0))
            .composited(over: CIImage(color: .white).cropped(to: rect.insetBy(dx: 0, dy: radius)))
        let corners = [
            CGPoint(x: rect.minX + radius, y: rect.minY + radius),
            CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
            CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
            CGPoint(x: rect.maxX - radius, y: rect.maxY - radius)
        ]
        return corners.reduce(base) { image, center in
            CIImage(color: .white)
                .cropped(to: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                .applyingFilter("CIRadialGradient", parameters: [
                    "inputCenter": CIVector(cgPoint: center),
                    "inputRadius0": radius - 1,
                    "inputRadius1": radius,
                    "inputColor0": CIColor.white,
                    "inputColor1": CIColor.clear
                ])
                .cropped(to: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                .composited(over: image)
        }
    }
}

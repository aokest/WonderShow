import AppKit
@preconcurrency import AVFoundation
import CoreImage
@preconcurrency import CoreMedia
import CoreVideo
import Foundation
import PresenterDirector
@preconcurrency import ScreenCaptureKit

enum ScreenCaptureSourcePreference: Hashable {
    case automaticPresentationWindow
    case entireDisplay
    case selectedDisplay(UInt32)
    case selectedWindows([UInt32])
}

enum ScreenArchiveRecorderError: Error, LocalizedError {
    case noDisplayAvailable
    case screenRecordingPermissionRequired
    case noActiveCaptureStream
    case noVideoFramesWritten(framesReceived: Int, writerError: String?)

    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            return "未找到可录制的显示器"
        case .screenRecordingPermissionRequired:
            return "需要在系统设置中允许灵演录制屏幕"
        case .noActiveCaptureStream:
            return "当前没有正在写入的屏幕录制流"
        case .noVideoFramesWritten(let framesReceived, let writerError):
            if let writerError, !writerError.isEmpty {
                return "屏幕原始轨没有写入视频帧（收到 \(framesReceived) 帧）：\(writerError)"
            }
            return "屏幕原始轨没有写入视频帧（收到 \(framesReceived) 帧）。请重新选择录制源或切到“整个屏幕”后再录制。"
        }
    }
}

enum ScreenCaptureSourceID: Hashable, Sendable {
    case display(UInt32)
    case window(UInt32)

    var displayID: UInt32? {
        if case .display(let id) = self {
            return id
        }
        return nil
    }

    var windowID: UInt32? {
        if case .window(let id) = self {
            return id
        }
        return nil
    }
}

struct ScreenCaptureWindowOption: Identifiable, Hashable, Sendable {
    let id: ScreenCaptureSourceID
    let applicationName: String
    let title: String
    let width: Int
    let height: Int

    var displayTitle: String {
        title.isEmpty ? applicationName : title
    }

    var iconName: String {
        switch id {
        case .display:
            return "display"
        case .window:
            return "macwindow"
        }
    }

    var detail: String {
        switch id {
        case .display:
            return "屏幕 · \(width)x\(height)"
        case .window:
            return "\(applicationName) · \(width)x\(height)"
        }
    }
}

struct ScreenCaptureSourceSnapshot: Hashable, Sendable {
    let options: [ScreenCaptureWindowOption]
    let displayCount: Int
    let windowCount: Int
    let permissionGranted: Bool
    let issue: String?

    var summary: String {
        if let issue {
            return issue
        }
        return "发现 \(displayCount) 个屏幕、\(windowCount) 个前台窗口，可共享 \(options.count) 个录制源"
    }
}

enum ScreenCapturePermissionStatus: Hashable, Sendable {
    case granted
    case denied
}

private final class ScreenSampleBuffer: @unchecked Sendable {
    let value: CMSampleBuffer

    init(_ value: CMSampleBuffer) {
        self.value = value
    }
}

final class ScreenArchiveRecorder: NSObject, @unchecked Sendable {
    struct CaptureSelection {
        let filter: SCContentFilter
        let width: Int
        let height: Int
    }

    struct CapturePixelSize: Equatable, Sendable {
        let width: Int
        let height: Int
    }

    struct RecordingSummary: Equatable, Sendable {
        let outputURL: URL?
        let framesReceived: Int
        let framesWritten: Int
        let outputFileSize: Int64
        let writerError: String?

        var isUsable: Bool {
            framesWritten > 0 && outputFileSize > 0
        }

        var issueDescription: String? {
            guard !isUsable else {
                return nil
            }
            return ScreenArchiveRecorderError
                .noVideoFramesWritten(framesReceived: framesReceived, writerError: writerError)
                .localizedDescription
        }
    }

    private struct ActiveRecording: @unchecked Sendable {
        let url: URL
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
    }

    private let queue = DispatchQueue(label: "com.lingyan.screen-archive-recorder")
    private let fileManager: FileManager
    private let previewContext = CIContext()
    private var stream: SCStream?
    private var outputURL: URL?
    private var activeRecording: ActiveRecording?
    private var isFinishing = false
    private var lastPreviewTimestamp = Date.distantPast
    private var framesReceived = 0
    private var framesWritten = 0
    private var frameIndex: CMTimeValue = 0
    private var isPaused = false
    private var framePump: DispatchSourceTimer?
    private var latestPixelBuffer: CVPixelBuffer?
    private var writerError: String?
    var onPreviewImage: (@MainActor (CGImage) -> Void)?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    static func availableWindowOptions() async throws -> [ScreenCaptureWindowOption] {
        try await ScreenCaptureSourceResolver.availableWindowOptions()
    }

    static func availableSourceSnapshot() async -> ScreenCaptureSourceSnapshot {
        await ScreenCaptureSourceResolver.availableSourceSnapshot()
    }

    static func requestScreenCapturePermission() -> ScreenCapturePermissionStatus {
        ScreenCaptureSourceResolver.requestPermission()
    }

    static func thumbnail(for sourceID: ScreenCaptureSourceID) async throws -> CGImage {
        try await ScreenCaptureSourceResolver.thumbnail(for: sourceID)
    }

    func startRecording(
        to outputURL: URL,
        target: PresentationTarget = .genericKeyboard,
        sourcePreference: ScreenCaptureSourcePreference = .automaticPresentationWindow
    ) async throws {
        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        let content = try await ScreenCaptureSourceResolver.shareableContent()
        guard let selection = ScreenCaptureSourceResolver.preferredSelection(
            from: content,
            target: target,
            sourcePreference: sourcePreference
        ) else {
            throw ScreenArchiveRecorderError.noDisplayAvailable
        }

        let configuration = Self.streamConfiguration(for: selection)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 5

        let stream = SCStream(filter: selection.filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        let recording = try makeRecording(
            url: outputURL,
            width: configuration.width,
            height: configuration.height
        )

        queue.sync {
            self.outputURL = outputURL
            self.activeRecording = recording
            self.isFinishing = false
            self.stream = stream
            self.framesReceived = 0
            self.framesWritten = 0
            self.frameIndex = 0
            self.isPaused = false
            self.latestPixelBuffer = nil
            self.writerError = nil
            self.startFramePumpOnQueue()
        }

        try await stream.startCapture()
    }

    func pauseRecording() {
        queue.async { [weak self] in
            self?.isPaused = true
        }
    }

    func resumeRecording() {
        queue.async { [weak self] in
            self?.isPaused = false
        }
    }

    func updateSource(
        target: PresentationTarget = .genericKeyboard,
        sourcePreference: ScreenCaptureSourcePreference = .automaticPresentationWindow
    ) async throws {
        let content = try await ScreenCaptureSourceResolver.shareableContent()
        guard let selection = ScreenCaptureSourceResolver.preferredSelection(
            from: content,
            target: target,
            sourcePreference: sourcePreference
        ) else {
            throw ScreenArchiveRecorderError.noDisplayAvailable
        }
        guard let stream = queue.sync(execute: { self.stream }) else {
            throw ScreenArchiveRecorderError.noActiveCaptureStream
        }
        try await stream.updateContentFilter(selection.filter)
        queue.async { [weak self] in
            self?.lastPreviewTimestamp = .distantPast
        }
    }

    @discardableResult
    func stopRecording() async -> RecordingSummary {
        let stream = queue.sync { self.stream }
        try? await stream?.stopCapture()

        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(
                        returning: RecordingSummary(
                            outputURL: nil,
                            framesReceived: 0,
                            framesWritten: 0,
                            outputFileSize: 0,
                            writerError: nil
                        )
                    )
                    return
                }
                finishWriterOnQueue { summary in
                    continuation.resume(returning: summary)
                }
            }
        }
    }

    static func capturePixelSize(
        width: Int,
        height: Int,
        displayID: UInt32? = nil,
        frame: CGRect?,
        displays: [SCDisplay],
        scaleFactor: CGFloat? = nil
    ) -> CapturePixelSize {
        let scale = max(1, scaleFactor ?? displayScaleFactor(displayID: displayID, containing: frame, displays: displays))
        let scaledWidth = Int((CGFloat(max(1, width)) * scale).rounded())
        let scaledHeight = Int((CGFloat(max(1, height)) * scale).rounded())
        return CapturePixelSize(
            width: evenPixelDimension(scaledWidth),
            height: evenPixelDimension(scaledHeight)
        )
    }

    static func streamConfiguration(for selection: CaptureSelection) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, selection.width)
        configuration.height = max(1, selection.height)
        configuration.showsCursor = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.scalesToFit = true
        if #available(macOS 14.0, *) {
            configuration.preservesAspectRatio = true
            configuration.captureResolution = .best
            configuration.shouldBeOpaque = true
        }
        return configuration
    }

    private static func evenPixelDimension(_ value: Int) -> Int {
        let bounded = max(2, value)
        return bounded.isMultiple(of: 2) ? bounded : bounded + 1
    }

    private static func displayScaleFactor(displayID explicitDisplayID: UInt32?, containing frame: CGRect?, displays: [SCDisplay]) -> CGFloat {
        let targetDisplayID: UInt32?
        if let explicitDisplayID {
            targetDisplayID = explicitDisplayID
        } else if let frame {
            targetDisplayID = ScreenCaptureSourceResolver.displayID(containing: frame, displays: displays)
        } else {
            targetDisplayID = displays.first?.displayID
        }

        guard let displayID = targetDisplayID,
              let screen = NSScreen.screens.first(where: { screen in
                  guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                      return false
                  }
                  return number.uint32Value == displayID
              }) else {
            return NSScreen.main?.backingScaleFactor ?? 1
        }
        return screen.backingScaleFactor
    }

    private func handle(sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid else {
            return
        }
        framesReceived += 1

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        latestPixelBuffer = imageBuffer
        publishPreviewIfNeeded(from: sampleBuffer)
    }

    private func makeRecording(url: URL, width: Int, height: Int) throws -> ActiveRecording {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoOutputSettings(width: width, height: height)
        )
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )

        guard writer.canAdd(input) else {
            throw ScreenArchiveRecorderError.noVideoFramesWritten(
                framesReceived: framesReceived,
                writerError: "AVAssetWriter 无法添加屏幕视频输入"
            )
        }
        writer.add(input)

        writer.startWriting()
        if writer.status == .failed {
            throw writer.error ?? ScreenArchiveRecorderError.noVideoFramesWritten(
                framesReceived: framesReceived,
                writerError: "AVAssetWriter 启动失败"
            )
        }
        writer.startSession(atSourceTime: .zero)
        return ActiveRecording(url: url, writer: writer, input: input, adaptor: adaptor)
    }

    private func startFramePumpOnQueue() {
        framePump?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(33), leeway: .milliseconds(4))
        timer.setEventHandler { [weak self] in
            self?.appendLatestFrameOnQueue()
        }
        framePump = timer
        timer.resume()
    }

    private func appendLatestFrameOnQueue() {
        guard !isFinishing,
              !isPaused,
              let recording = activeRecording,
              let latestPixelBuffer else {
            return
        }

        guard recording.writer.status == .writing else {
            writerError = recording.writer.error?.localizedDescription
                ?? "AVAssetWriter 状态异常：\(recording.writer.status.rawValue)"
            return
        }

        let presentationTime = CMTime(value: frameIndex, timescale: 30)
        frameIndex += 1
        guard recording.input.isReadyForMoreMediaData else {
            return
        }

        if recording.adaptor.append(latestPixelBuffer, withPresentationTime: presentationTime) {
            framesWritten += 1
        } else {
            writerError = recording.writer.error?.localizedDescription ?? "屏幕视频写入器拒绝了最新画面"
        }
    }

    private func finishWriterOnQueue(completion: @escaping @Sendable (RecordingSummary) -> Void) {
        framePump?.cancel()
        framePump = nil
        latestPixelBuffer = nil
        isPaused = false
        let finishedOutputURL = outputURL
        stream = nil
        outputURL = nil
        guard let recording = activeRecording, !isFinishing else {
            let summary = makeSummary(outputURL: finishedOutputURL)
            activeRecording = nil
            isFinishing = false
            completion(summary)
            return
        }

        isFinishing = true
        activeRecording = nil
        recording.input.markAsFinished()
        recording.writer.finishWriting { [weak self] in
            guard let self else {
                completion(
                    RecordingSummary(
                        outputURL: finishedOutputURL,
                        framesReceived: 0,
                        framesWritten: 0,
                        outputFileSize: 0,
                        writerError: nil
                    )
                )
                return
            }
            let finishedWriterError = recording.writer.error?.localizedDescription
            queue.async {
                if let finishedWriterError {
                    self.writerError = finishedWriterError
                }
                self.isFinishing = false
                completion(self.makeSummary(outputURL: finishedOutputURL))
            }
        }
    }

    private func makeSummary(outputURL: URL?) -> RecordingSummary {
        let size: Int64
        if let outputURL {
            size = (try? fileManager.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?
                .int64Value ?? 0
        } else {
            size = 0
        }
        return RecordingSummary(
            outputURL: outputURL,
            framesReceived: framesReceived,
            framesWritten: framesWritten,
            outputFileSize: size,
            writerError: writerError
        )
    }

    private func videoOutputSettings(width: Int, height: Int) -> [String: Any] {
        return [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: max(2, width),
            AVVideoHeightKey: max(2, height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(8_000_000, width * height * 2)
            ]
        ]
    }

    private func publishPreviewIfNeeded(from sampleBuffer: CMSampleBuffer) {
        guard let onPreviewImage else {
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastPreviewTimestamp) >= 0.3 else {
            return
        }
        lastPreviewTimestamp = now

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let image = previewContext.createCGImage(ciImage, from: ciImage.extent) else {
            return
        }

        Task { @MainActor in
            onPreviewImage(image)
        }
    }
}

enum ScreenCaptureSourceResolver {
    static func requestPermission() -> ScreenCapturePermissionStatus {
        CGRequestScreenCaptureAccess() ? .granted : .denied
    }

    static func shareableContent() async throws -> SCShareableContent {
        guard CGPreflightScreenCaptureAccess() else {
            throw ScreenArchiveRecorderError.screenRecordingPermissionRequired
        }

        return try await shareableContent(onScreenWindowsOnly: false)
    }

    private static func pickerShareableContent() async throws -> SCShareableContent {
        guard CGPreflightScreenCaptureAccess() else {
            throw ScreenArchiveRecorderError.screenRecordingPermissionRequired
        }

        return try await shareableContent(onScreenWindowsOnly: true)
    }

    private static func shareableContent(onScreenWindowsOnly: Bool) async throws -> SCShareableContent {
        return try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: onScreenWindowsOnly
        )
    }

    static func availableWindowOptions() async throws -> [ScreenCaptureWindowOption] {
        let content = try await pickerShareableContent()
        return sourceOptions(from: content)
    }

    static func availableSourceSnapshot() async -> ScreenCaptureSourceSnapshot {
        guard CGPreflightScreenCaptureAccess() else {
            return ScreenCaptureSourceSnapshot(
                options: [],
                displayCount: 0,
                windowCount: 0,
                permissionGranted: false,
                issue: ScreenArchiveRecorderError.screenRecordingPermissionRequired.localizedDescription
            )
        }

        do {
            let content = try await pickerShareableContent()
            return ScreenCaptureSourceSnapshot(
                options: sourceOptions(from: content),
                displayCount: content.displays.count,
                windowCount: content.windows.count,
                permissionGranted: true,
                issue: nil
            )
        } catch {
            return ScreenCaptureSourceSnapshot(
                options: [],
                displayCount: 0,
                windowCount: 0,
                permissionGranted: false,
                issue: error.localizedDescription
            )
        }
    }

    static func thumbnail(for sourceID: ScreenCaptureSourceID) async throws -> CGImage {
        let content = try await shareableContent()
        guard let selection = selection(for: sourceID, from: content) else {
            throw ScreenArchiveRecorderError.noDisplayAvailable
        }

        let maxWidth: CGFloat = 520
        let maxHeight: CGFloat = 320
        let sourceWidth = CGFloat(max(1, selection.width))
        let sourceHeight = CGFloat(max(1, selection.height))
        let scale = min(maxWidth / sourceWidth, maxHeight / sourceHeight, 1)

        let configuration = ScreenArchiveRecorder.streamConfiguration(for: selection)
        configuration.width = max(1, Int(sourceWidth * scale))
        configuration.height = max(1, Int(sourceHeight * scale))

        return try await SCScreenshotManager.captureImage(
            contentFilter: selection.filter,
            configuration: configuration
        )
    }

    private static func sourceOptions(from content: SCShareableContent) -> [ScreenCaptureWindowOption] {
        let displayOptions = content.displays
            .sorted { ($0.width * $0.height) > ($1.width * $1.height) }
            .enumerated()
            .map { index, display in
                ScreenCaptureWindowOption(
                    id: .display(display.displayID),
                    applicationName: "Display",
                    title: "屏幕 \(index + 1)",
                    width: display.width,
                    height: display.height
                )
            }

        let windowOptions = content.windows
            .filter { window in
                let candidate = CaptureWindowCandidate(
                    id: window.windowID,
                    displayID: displayID(containing: window.frame, displays: content.displays),
                    title: window.title ?? "",
                    applicationName: window.owningApplication?.applicationName ?? "",
                    bundleIdentifier: window.owningApplication?.bundleIdentifier ?? "",
                    frameWidth: Int(window.frame.width),
                    frameHeight: Int(window.frame.height)
                )
                return ScreenSharingWindowFilter().isShareable(candidate)
            }
            .compactMap { window -> ScreenCaptureWindowOption? in
                let title = (window.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let applicationName = (window.owningApplication?.applicationName ?? "Unknown")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let width = Int(window.frame.width)
                let height = Int(window.frame.height)
                guard width >= 80, height >= 60 else {
                    return nil
                }
                guard !title.isEmpty || !applicationName.isEmpty else {
                    return nil
                }
                return ScreenCaptureWindowOption(
                    id: .window(window.windowID),
                    applicationName: applicationName.isEmpty ? "Unknown" : applicationName,
                    title: title,
                    width: width,
                    height: height
                )
            }
            .sorted {
                if $0.applicationName == $1.applicationName {
                    return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
                }
                return $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName) == .orderedAscending
            }

        return displayOptions + windowOptions
    }

    private static func selection(
        for sourceID: ScreenCaptureSourceID,
        from content: SCShareableContent
    ) -> ScreenArchiveRecorder.CaptureSelection? {
        switch sourceID {
        case .display(let displayID):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                return nil
            }
            let pixelSize = ScreenArchiveRecorder.capturePixelSize(
                width: display.width,
                height: display.height,
                displayID: display.displayID,
                frame: nil,
                displays: content.displays
            )
            return ScreenArchiveRecorder.CaptureSelection(
                filter: SCContentFilter(display: display, excludingWindows: []),
                width: pixelSize.width,
                height: pixelSize.height
            )
        case .window(let windowID):
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                return nil
            }
            let pixelSize = ScreenArchiveRecorder.capturePixelSize(
                width: max(1, Int(window.frame.width)),
                height: max(1, Int(window.frame.height)),
                frame: window.frame,
                displays: content.displays
            )
            return ScreenArchiveRecorder.CaptureSelection(
                filter: SCContentFilter(desktopIndependentWindow: window),
                width: pixelSize.width,
                height: pixelSize.height
            )
        }
    }

    static func preferredSelection(
        from content: SCShareableContent,
        target: PresentationTarget,
        sourcePreference: ScreenCaptureSourcePreference
    ) -> ScreenArchiveRecorder.CaptureSelection? {
        let displays = content.displays.map {
            CaptureDisplayCandidate(
                id: $0.displayID,
                width: $0.width,
                height: $0.height
            )
        }
        let windows = content.windows.map {
            let windowFrame = $0.frame
            return CaptureWindowCandidate(
                id: $0.windowID,
                displayID: displayID(containing: windowFrame, displays: content.displays),
                title: $0.title ?? "",
                applicationName: $0.owningApplication?.applicationName ?? "",
                bundleIdentifier: $0.owningApplication?.bundleIdentifier ?? "",
                frameWidth: Int(windowFrame.width),
                frameHeight: Int(windowFrame.height)
            )
        }

        if case .selectedDisplay(let displayID) = sourcePreference,
           let display = content.displays.first(where: { $0.displayID == displayID }) {
            let pixelSize = ScreenArchiveRecorder.capturePixelSize(
                width: display.width,
                height: display.height,
                displayID: display.displayID,
                frame: nil,
                displays: content.displays
            )
            return ScreenArchiveRecorder.CaptureSelection(
                filter: SCContentFilter(display: display, excludingWindows: []),
                width: pixelSize.width,
                height: pixelSize.height
            )
        }

        if case .selectedWindows(let windowIDs) = sourcePreference {
            let selectedWindows = content.windows.filter { windowIDs.contains($0.windowID) }
            if let selection = selectedWindowSelection(
                windows: selectedWindows,
                displays: content.displays
            ) {
                return selection
            }
        }

        let planner = ScreenCapturePlanner()
        if sourcePreference == .automaticPresentationWindow {
            if let plannedWindow = planner.preferredWindow(windows: windows, target: target),
               let window = content.windows.first(where: { $0.windowID == plannedWindow.id }) {
                let pixelSize = ScreenArchiveRecorder.capturePixelSize(
                    width: max(1, Int(window.frame.width)),
                    height: max(1, Int(window.frame.height)),
                    frame: window.frame,
                    displays: content.displays
                )
                return ScreenArchiveRecorder.CaptureSelection(
                    filter: SCContentFilter(desktopIndependentWindow: window),
                    width: pixelSize.width,
                    height: pixelSize.height
                )
            }
        }

        guard let plannedDisplay = planner.preferredDisplay(
            displays: displays,
            windows: windows,
            target: target
        ) else {
            return nil
        }

        guard let display = content.displays.first(where: { $0.displayID == plannedDisplay.id }) else {
            return nil
        }

        let pixelSize = ScreenArchiveRecorder.capturePixelSize(
            width: display.width,
            height: display.height,
            displayID: display.displayID,
            frame: nil,
            displays: content.displays
        )

        return ScreenArchiveRecorder.CaptureSelection(
            filter: SCContentFilter(display: display, excludingWindows: []),
            width: pixelSize.width,
            height: pixelSize.height
        )
    }

    private static func selectedWindowSelection(
        windows: [SCWindow],
        displays: [SCDisplay]
    ) -> ScreenArchiveRecorder.CaptureSelection? {
        guard !windows.isEmpty else {
            return nil
        }

        if windows.count == 1, let window = windows.first {
            let pixelSize = ScreenArchiveRecorder.capturePixelSize(
                width: max(1, Int(window.frame.width)),
                height: max(1, Int(window.frame.height)),
                frame: window.frame,
                displays: displays
            )
            return ScreenArchiveRecorder.CaptureSelection(
                filter: SCContentFilter(desktopIndependentWindow: window),
                width: pixelSize.width,
                height: pixelSize.height
            )
        }

        guard let display = display(containing: windows, displays: displays) else {
            return nil
        }

        let displayWindows = windows.filter {
            displayID(containing: $0.frame, displays: displays) == display.displayID
        }
        let includedWindows = displayWindows.isEmpty ? windows : displayWindows
        let pixelSize = ScreenArchiveRecorder.capturePixelSize(
            width: display.width,
            height: display.height,
            displayID: display.displayID,
            frame: nil,
            displays: displays
        )
        return ScreenArchiveRecorder.CaptureSelection(
            filter: SCContentFilter(display: display, including: includedWindows),
            width: pixelSize.width,
            height: pixelSize.height
        )
    }

    private static func display(containing windows: [SCWindow], displays: [SCDisplay]) -> SCDisplay? {
        let displayIDs = windows.map { displayID(containing: $0.frame, displays: displays) }
        if let preferredID = displayIDs.first,
           let display = displays.first(where: { $0.displayID == preferredID }) {
            return display
        }
        return displays.first
    }

    static func displayID(containing windowFrame: CGRect, displays: [SCDisplay]) -> UInt32 {
        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return displays.first?.displayID ?? 0
        }

        let displayID = number.uint32Value
        return displays.contains(where: { $0.displayID == displayID })
            ? displayID
            : (displays.first?.displayID ?? displayID)
    }
}

extension ScreenArchiveRecorder: SCStreamOutput, SCStreamDelegate {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen else {
            return
        }
        let queuedSampleBuffer = ScreenSampleBuffer(sampleBuffer)
        queue.async { [weak self, queuedSampleBuffer] in
            self?.handle(sampleBuffer: queuedSampleBuffer.value)
        }
    }
}

import Foundation
import WonderShow

enum RecordingTimelineFileState: String, Codable, Hashable, Sendable {
    case missing
    case writing
    case ready
}

struct RecordingTimelineSegmentModel: Codable, Hashable, Sendable {
    let startMilliseconds: Int
    let endMilliseconds: Int
    let label: String
    let fraction: Double
}

struct RecordingTimelineTrackRowModel: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let role: RecordingTrackRole?
    let title: String
    let detail: String
    let state: RecordingTimelineFileState
    let segments: [RecordingTimelineSegmentModel]
}

enum RecordingTimelineTrackModel {
    static func rows(
        manifest: RecordingProjectManifest,
        fileStates: [String: RecordingTimelineFileState],
        fallbackDurationMilliseconds: Int
    ) -> [RecordingTimelineTrackRowModel] {
        let duration = max(1, manifest.project.timeline.durationMilliseconds, fallbackDurationMilliseconds)
        let segments = manifest.project.timeline.segments.map { segment in
            RecordingTimelineSegmentModel(
                startMilliseconds: segment.startMilliseconds,
                endMilliseconds: segment.endMilliseconds,
                label: segment.scene.view.timelineLabel,
                fraction: Double(segment.endMilliseconds - segment.startMilliseconds) / Double(duration)
            )
        }
        var rows: [RecordingTimelineTrackRowModel] = []
        let assetsByRole = Dictionary(
            uniqueKeysWithValues: manifest.mediaAssets.compactMap { asset in
                asset.trackRole.map { ($0, asset) }
            }
        )

        appendTrack(
            role: .slidesScreen,
            title: "PPT/屏幕",
            detail: assetsByRole[.slidesScreen]?.relativePath ?? "Raw/slides-screen.mov",
            assetsByRole: assetsByRole,
            fileStates: fileStates,
            segments: segments,
            rows: &rows
        )
        appendTrack(
            role: .presenterCamera,
            title: "讲者",
            detail: assetsByRole[.presenterCamera]?.relativePath ?? "Raw/presenter-camera.mov",
            assetsByRole: assetsByRole,
            fileStates: fileStates,
            segments: segments,
            rows: &rows
        )
        appendTrack(
            role: .microphoneAudio,
            title: "声音",
            detail: assetsByRole[.microphoneAudio]?.relativePath ?? "Raw/microphone.m4a",
            assetsByRole: assetsByRole,
            fileStates: fileStates,
            segments: segments,
            rows: &rows
        )

        if let programAsset = manifest.mediaAssets.first(where: { $0.output == manifest.project.programOutput }) {
            rows.append(
                RecordingTimelineTrackRowModel(
                    id: "program",
                    role: nil,
                    title: "合成",
                    detail: programAsset.relativePath,
                    state: fileStates[programAsset.relativePath] ?? .missing,
                    segments: segments
                )
            )
        }
        return rows
    }

    private static func appendTrack(
        role: RecordingTrackRole,
        title: String,
        detail: String,
        assetsByRole: [RecordingTrackRole: RecordingMediaAsset],
        fileStates: [String: RecordingTimelineFileState],
        segments: [RecordingTimelineSegmentModel],
        rows: inout [RecordingTimelineTrackRowModel]
    ) {
        guard let asset = assetsByRole[role] else {
            return
        }
        rows.append(
            RecordingTimelineTrackRowModel(
                id: role.rawID,
                role: role,
                title: title,
                detail: detail,
                state: fileStates[asset.relativePath] ?? .missing,
                segments: segments
            )
        )
    }
}

struct TimelineExportRange: Codable, Hashable, Sendable {
    let startMilliseconds: Int
    let endMilliseconds: Int
}

struct TimelineSelection: Codable, Hashable, Sendable {
    var ranges: [TimelineExportRange]

    func normalized(durationMilliseconds: Int) -> TimelineSelection {
        let duration = max(1, durationMilliseconds)
        let normalizedRanges = ranges.compactMap { range -> TimelineExportRange? in
            let start = min(max(0, range.startMilliseconds), duration)
            let end = min(max(0, range.endMilliseconds), duration)
            guard start < end else {
                return nil
            }
            return TimelineExportRange(startMilliseconds: start, endMilliseconds: end)
        }
        return TimelineSelection(ranges: normalizedRanges)
    }
}

private extension RecordingTrackRole {
    var rawID: String {
        switch self {
        case .presenterCamera:
            return "presenterCamera"
        case .slidesScreen:
            return "slidesScreen"
        case .microphoneAudio:
            return "microphoneAudio"
        }
    }
}

private extension ProgramView {
    var timelineLabel: String {
        switch self {
        case .speakerFullBody:
            return "全身"
        case .speakerCloseUp:
            return "特写"
        case .slidesWithSpeakerPictureInPicture:
            return "屏幕主"
        case .speakerWithSlidesPictureInPicture:
            return "讲者主"
        case .sideBySide:
            return "分屏"
        case .topBottom:
            return "上下"
        case .slidesFullScreen:
            return "屏幕"
        }
    }
}

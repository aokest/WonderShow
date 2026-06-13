import PresenterDirector
import SwiftUI

struct DashboardView: View {
    @State private var target: PresentationTarget = .powerPoint
    @State private var mode: RecordingMode = .cameraAndScreen
    @State private var layout: RecordingLayout = .screenWithCameraPictureInPicture(corner: .bottomRight)

    private let director = PresentationDirector()
    private let pipelineFactory = RecordingPipelineFactory()

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    previewPanel
                    compatibilityPanel
                }

                VStack(spacing: 16) {
                    devicePanel
                    recordingPanel
                    gesturePanel
                    htmlPanel
                }
                .frame(width: 340)
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Presenter Director")
                    .font(.system(size: 26, weight: .semibold))
                Text("Pocket 3 speaker tracking, gesture slide control, and presentation recording")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Start Rehearsal") {}
                .buttonStyle(.borderedProminent)
            Button("Record") {}
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Program Preview", systemImage: "rectangle.inset.filled.and.person.filled")
                .font(.headline)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black)
                VStack(spacing: 10) {
                    Image(systemName: "video")
                        .font(.system(size: 42))
                    Text("AVFoundation camera preview connects here")
                        .font(.headline)
                    Text("Next phase: bind this panel to the OsmoPocket3 UVC stream.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
            }
            .aspectRatio(16 / 9, contentMode: .fit)
        }
        .panelStyle()
    }

    private var compatibilityPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Presentation Target", systemImage: "play.rectangle.on.rectangle")
                .font(.headline)

            Picker("Target", selection: $target) {
                Text("PowerPoint").tag(PresentationTarget.powerPoint)
                Text("WPS").tag(PresentationTarget.wps)
                Text("Keynote").tag(PresentationTarget.keynote)
                Text("PDF").tag(PresentationTarget.pdfViewer)
                Text("HTML / Reveal.js").tag(PresentationTarget.html(engine: .revealJS))
            }
            .pickerStyle(.segmented)

            HStack {
                SummaryPill(title: "Slide Control", value: commandSummary)
                SummaryPill(title: "Annotation", value: annotationSummary)
            }
        }
        .panelStyle()
    }

    private var devicePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Camera", systemImage: "camera")
                .font(.headline)

            DetailRow(label: "Device", value: DeviceCapability.pocket3.name)
            DetailRow(label: "Interface", value: "UVC camera")
            DetailRow(label: "Tracking", value: "Pocket 3 on-device FaceTrack")
            DetailRow(label: "Private SDK", value: DeviceCapability.pocket3.requiresPrivateGimbalSDK ? "Required" : "Not required")
        }
        .panelStyle()
    }

    private var recordingPanel: some View {
        let pipeline = pipelineFactory.makePipeline(
            mode: mode,
            camera: .pocket3,
            screen: mode == .cameraAndScreen ? .mainDisplay : nil,
            layout: layout
        )

        return VStack(alignment: .leading, spacing: 12) {
            Label("Recording", systemImage: "record.circle")
                .font(.headline)

            Picker("Mode", selection: $mode) {
                Text("Speaker Only").tag(RecordingMode.cameraOnly)
                Text("Speaker + Screen").tag(RecordingMode.cameraAndScreen)
            }
            .pickerStyle(.segmented)

            Picker("Layout", selection: $layout) {
                Text("Close-up").tag(RecordingLayout.speakerCloseUp)
                Text("Picture in Picture").tag(RecordingLayout.screenWithCameraPictureInPicture(corner: .bottomRight))
                Text("Side by Side").tag(RecordingLayout.sideBySide)
            }

            DetailRow(label: "Inputs", value: "\(pipeline.inputs.count)")
            DetailRow(label: "Outputs", value: pipeline.outputs.map(\.label).joined(separator: ", "))
            DetailRow(label: "Composition", value: pipeline.composition.label)
        }
        .panelStyle()
    }

    private var gesturePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Gestures", systemImage: "hand.raised")
                .font(.headline)

            DetailRow(label: "Swipe left", value: "Next slide")
            DetailRow(label: "Swipe right", value: "Previous slide")
            DetailRow(label: "Pinch", value: "Toggle annotation")
            DetailRow(label: "Open palm", value: "Clear marks")
        }
        .panelStyle()
    }

    private var htmlPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("HTML Mode", systemImage: "curlybraces")
                .font(.headline)

            Text("HTML decks can use a local bridge and in-slide canvas, so drawing, undo, clearing, and exporting marks are more reliable than controlling Office ink tools.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }

    private var commandSummary: String {
        director.command(for: .swipeLeft, target: target).transport.label
    }

    private var annotationSummary: String {
        director.annotationStrategy(for: target).label
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}

private struct SummaryPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private extension View {
    func panelStyle() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }
}

private extension CommandTransport {
    var label: String {
        switch self {
        case .keyboardShortcut:
            return "Keyboard"
        case .accessibilityAutomation:
            return "Accessibility"
        case .htmlBridge:
            return "HTML bridge"
        case .internalOverlay:
            return "Overlay"
        }
    }
}

private extension AnnotationStrategy {
    var label: String {
        switch self {
        case .systemOverlay:
            return "System overlay"
        case .inSlideCanvas:
            return "In-slide canvas"
        }
    }
}

private extension RecordingOutput {
    var label: String {
        switch self {
        case .cameraArchive:
            return "camera"
        case .screenArchive:
            return "screen"
        case .programRecording:
            return "program"
        }
    }
}

private extension ProgramComposition {
    var label: String {
        switch self {
        case .singleCamera:
            return "Speaker close-up"
        case .pictureInPicture:
            return "Picture in picture"
        case .sideBySide:
            return "Side by side"
        }
    }
}

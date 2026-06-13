public enum CameraDevice: Hashable, Sendable {
    case pocket3
    case builtInFaceTime
    case external(name: String)
}

public enum ScreenSource: Hashable, Sendable {
    case mainDisplay
    case display(id: UInt32)
    case window(id: UInt32)
}

public enum RecordingInput: Hashable, Sendable {
    case camera(CameraDevice)
    case screen(ScreenSource)
}

public enum RecordingOutput: Hashable, Sendable {
    case cameraArchive
    case screenArchive
    case programRecording
}

public enum PiPCorner: Hashable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

public enum RecordingMode: Hashable, Sendable {
    case cameraOnly
    case cameraAndScreen
}

public enum RecordingLayout: Hashable, Sendable {
    case speakerCloseUp
    case screenWithCameraPictureInPicture(corner: PiPCorner)
    case sideBySide
}

public enum ProgramComposition: Hashable, Sendable {
    case singleCamera
    case pictureInPicture(corner: PiPCorner)
    case sideBySide
}

public struct RecordingPipeline: Hashable, Sendable {
    public let inputs: [RecordingInput]
    public let outputs: [RecordingOutput]
    public let composition: ProgramComposition

    public init(inputs: [RecordingInput], outputs: [RecordingOutput], composition: ProgramComposition) {
        self.inputs = inputs
        self.outputs = outputs
        self.composition = composition
    }
}

public struct RecordingPipelineFactory: Sendable {
    public init() {}

    public func makePipeline(
        mode: RecordingMode,
        camera: CameraDevice,
        screen: ScreenSource?,
        layout: RecordingLayout
    ) -> RecordingPipeline {
        switch mode {
        case .cameraOnly:
            return RecordingPipeline(
                inputs: [.camera(camera)],
                outputs: [.cameraArchive, .programRecording],
                composition: .singleCamera
            )

        case .cameraAndScreen:
            var inputs: [RecordingInput] = [.camera(camera)]
            if let screen {
                inputs.append(.screen(screen))
            }

            return RecordingPipeline(
                inputs: inputs,
                outputs: [.cameraArchive, .screenArchive, .programRecording],
                composition: composition(for: layout)
            )
        }
    }

    private func composition(for layout: RecordingLayout) -> ProgramComposition {
        switch layout {
        case .speakerCloseUp:
            return .singleCamera
        case .screenWithCameraPictureInPicture(let corner):
            return .pictureInPicture(corner: corner)
        case .sideBySide:
            return .sideBySide
        }
    }
}

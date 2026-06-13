public enum HtmlPresentationEngine: Hashable, Sendable {
    case revealJS
    case slidev
    case custom
}

public enum PresentationTarget: Hashable, Sendable {
    case powerPoint
    case wps
    case keynote
    case pdfViewer
    case genericKeyboard
    case html(engine: HtmlPresentationEngine)
}

public enum AnnotationStrategy: Hashable, Sendable {
    case systemOverlay
    case inSlideCanvas
}

public final class PresentationDirector {
    private let cooldownMilliseconds: Int
    private var acceptedGestureTimes: [GestureIntent: Int] = [:]

    public init(cooldownMilliseconds: Int = 700) {
        self.cooldownMilliseconds = cooldownMilliseconds
    }

    public func command(for gesture: GestureIntent, target: PresentationTarget) -> DirectorCommand {
        let transport = transport(for: target)

        switch gesture {
        case .swipeLeft:
            return DirectorCommand(presentationAction: .nextSlide, transport: transport)
        case .swipeRight:
            return DirectorCommand(presentationAction: .previousSlide, transport: transport)
        case .zoomIn:
            return DirectorCommand(presentationAction: .zoomIn, transport: transport)
        case .zoomOut:
            return DirectorCommand(presentationAction: .zoomOut, transport: transport)
        case .pinchToggle:
            return DirectorCommand(presentationAction: .toggleAnnotation, transport: annotationTransport(for: target))
        case .pinchDrag:
            return DirectorCommand(presentationAction: .drawAnnotation, transport: annotationTransport(for: target))
        case .openPalmHold:
            return DirectorCommand(presentationAction: .clearAnnotations, transport: annotationTransport(for: target))
        }
    }

    public func accepts(_ gesture: GestureIntent, atMilliseconds timestamp: Int) -> Bool {
        guard let previousTimestamp = acceptedGestureTimes[gesture] else {
            acceptedGestureTimes[gesture] = timestamp
            return true
        }

        let elapsed = timestamp - previousTimestamp
        guard elapsed >= cooldownMilliseconds else {
            return false
        }

        acceptedGestureTimes[gesture] = timestamp
        return true
    }

    public func annotationStrategy(for target: PresentationTarget) -> AnnotationStrategy {
        switch target {
        case .html:
            return .inSlideCanvas
        case .powerPoint, .wps, .keynote, .pdfViewer, .genericKeyboard:
            return .systemOverlay
        }
    }

    private func transport(for target: PresentationTarget) -> CommandTransport {
        switch target {
        case .html:
            return .htmlBridge
        case .powerPoint, .wps, .keynote, .pdfViewer, .genericKeyboard:
            return .keyboardShortcut
        }
    }

    private func annotationTransport(for target: PresentationTarget) -> CommandTransport {
        switch annotationStrategy(for: target) {
        case .inSlideCanvas:
            return .htmlBridge
        case .systemOverlay:
            return .internalOverlay
        }
    }
}

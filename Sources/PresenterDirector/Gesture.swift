public enum GestureIntent: Hashable, Sendable {
    case swipeLeft
    case swipeRight
    case pinchToggle
    case pinchDrag
    case openPalmHold
}

public enum PresentationAction: Hashable, Sendable {
    case nextSlide
    case previousSlide
    case toggleAnnotation
    case drawAnnotation
    case clearAnnotations
    case none
}

public enum CommandTransport: Hashable, Sendable {
    case keyboardShortcut
    case accessibilityAutomation
    case htmlBridge
    case internalOverlay
}

public struct DirectorCommand: Hashable, Sendable {
    public let presentationAction: PresentationAction
    public let transport: CommandTransport

    public init(presentationAction: PresentationAction, transport: CommandTransport) {
        self.presentationAction = presentationAction
        self.transport = transport
    }
}

import Foundation
import Network
import PresenterDirector

final class DemoControlServer: @unchecked Sendable {
    static let shared = DemoControlServer()

    private let queue = DispatchQueue(label: "com.lingyan.demo-control-server")
    private let port: NWEndpoint.Port = 17635
    private let host: NWEndpoint.Host = "127.0.0.1"
    private var listener: NWListener?
    private var pendingCommands: [DemoBridgeCommand] = []

    var demoURL: URL {
        URL(string: "http://127.0.0.1:\(port.rawValue)/wondershow-demo.html#token=\(WonderShowLocalSecurity.tokenQueryValue())")!
    }

    var demoDisplayURL: URL {
        URL(string: "http://127.0.0.1:\(port.rawValue)/wondershow-demo.html")!
    }

    var isRunning: Bool {
        queue.sync { listener != nil }
    }

    private init() {}

    func start() throws {
        guard queue.sync(execute: { self.listener == nil }) else { return }

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: host, port: port)
        let newListener = try NWListener(using: parameters)
        newListener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        newListener.start(queue: queue)
        queue.sync {
            self.listener = newListener
        }
    }

    func enqueue(_ command: String, swipeVelocity: Double? = nil) throws {
        try start()
        queue.async { [weak self] in
            self?.pendingCommands.append(.simple(command, swipeVelocity: swipeVelocity))
            // #region debug-point D:enqueue-command
            self?.debugReport(
                hypothesisId: "D",
                location: "DemoControlServer.enqueue",
                message: "[DEBUG] bridge command enqueued",
                data: [
                    "command": command,
                    "pendingCount": self?.pendingCommands.count ?? -1
                ]
            )
            // #endregion
        }
    }

    func enqueueZoom(scale: Double) throws {
        try start()
        queue.async { [weak self] in
            self?.pendingCommands.append(.setZoom(scale))
            // #region debug-point D:enqueue-zoom
            self?.debugReport(
                hypothesisId: "D",
                location: "DemoControlServer.enqueueZoom",
                message: "[DEBUG] bridge zoom enqueued",
                data: [
                    "scale": scale,
                    "pendingCount": self?.pendingCommands.count ?? -1
                ]
            )
            // #endregion
        }
    }

    func enqueuePan(x: Double, y: Double) throws {
        try start()
        queue.async { [weak self] in
            self?.pendingCommands.append(.setPan(x: x, y: y))
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }

            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let response = self.response(for: request)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    #if DEBUG
    func responseForTesting(_ request: String) -> Data {
        response(for: request)
    }
    #endif

    private func response(for request: String) -> Data {
        let requestTarget = request
            .components(separatedBy: "\r\n")
            .first?
            .split(separator: " ")
            .dropFirst()
            .first
            .map(String.init) ?? "/"
        let path = URLComponents(string: "http://127.0.0.1\(requestTarget)")?.path ?? requestTarget

        switch path {
        case "/", "/wondershow-demo.html":
            return httpResponse(body: demoHTML(), contentType: "text/html; charset=utf-8")
        case "/api/command":
            guard isAuthorized(request) else {
                return unauthorizedResponse()
            }
            let command = pendingCommands.isEmpty ? nil : pendingCommands.removeFirst()
            // #region debug-point D:dequeue-command
            debugReport(
                hypothesisId: "D",
                location: "DemoControlServer.response",
                message: "[DEBUG] bridge command polled",
                data: [
                    "path": path,
                    "command": command?.json ?? "null",
                    "remainingCount": pendingCommands.count
                ]
            )
            // #endregion
            let body = command?.json ?? #"{"command":null}"#
            return httpResponse(body: body, contentType: "application/json; charset=utf-8")
        case "/api/status":
            guard isAuthorized(request) else {
                return unauthorizedResponse()
            }
            return httpResponse(body: #"{"ok":true}"#, contentType: "application/json; charset=utf-8")
        default:
            return httpResponse(status: "404 Not Found", body: "Not found", contentType: "text/plain; charset=utf-8")
        }
    }

    private func demoHTML() -> String {
        for candidate in Self.demoHTMLCandidates() {
            if let html = try? String(contentsOf: candidate, encoding: .utf8) {
                return html
            }
        }
        return "<!doctype html><title>灵演测试页</title><body>无法加载测试演示页</body>"
    }

    private func httpResponse(status: String = "200 OK", body: String, contentType: String) -> Data {
        let bodyData = Data(body.utf8)
        let header = """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType)\r
        Content-Length: \(bodyData.count)\r
        Cache-Control: no-store\r
        Connection: close\r
        \r

        """
        var data = Data(header.utf8)
        data.append(bodyData)
        return data
    }

    private func unauthorizedResponse() -> Data {
        httpResponse(
            status: "401 Unauthorized",
            body: #"{"ok":false,"error":"Unauthorized"}"#,
            contentType: "application/json; charset=utf-8"
        )
    }

    private func isAuthorized(_ request: String) -> Bool {
        WonderShowLocalSecurity.isAuthorized(header(named: WonderShowLocalSecurity.headerName, in: request))
    }

    private func header(named name: String, in request: String) -> String? {
        let prefix = "\(name.lowercased()):"
        return request
            .components(separatedBy: "\r\n")
            .dropFirst()
            .first { $0.lowercased().hasPrefix(prefix) }
            .map { line in
                String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
    }

    private static func demoHTMLCandidates() -> [URL] {
        let bundleURL = Bundle.main.bundleURL
        return [
            Bundle.main.url(forResource: "wondershow-demo", withExtension: "html"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("examples/wondershow-demo.html"),
            bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("examples/wondershow-demo.html")
        ].compactMap { $0 }
    }

    // #region debug-point Z:report-helper
    private func debugReport(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: Any]
    ) {
        #if DEBUG
        guard let url = URL(string: "http://127.0.0.1:7777/event") else { return }
        guard JSONSerialization.isValidJSONObject(data) else { return }
        let payload: [String: Any] = [
            "sessionId": "gesture-regression-loop",
            "runId": "post-fix",
            "hypothesisId": hypothesisId,
            "location": location,
            "msg": message,
            "data": data,
            "ts": Int(Date().timeIntervalSince1970 * 1_000)
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        URLSession.shared.dataTask(with: request).resume()
        #else
        _ = hypothesisId
        _ = location
        _ = message
        _ = data
        #endif
    }
    // #endregion
}

private enum DemoBridgeCommand {
    case simple(String, swipeVelocity: Double?)
    case setZoom(Double)
    case setPan(x: Double, y: Double)

    var json: String {
        switch self {
        case .simple(let command, let swipeVelocity):
            if let swipeVelocity {
                return #"{"command":"\#(command)","value":{"velocity":\#(swipeVelocity)}}"#
            }
            return #"{"command":"\#(command)"}"#
        case .setZoom(let scale):
            return #"{"command":"setZoom","value":\#(scale)}"#
        case .setPan(let x, let y):
            return #"{"command":"setPan","value":{"x":\#(x),"y":\#(y)}}"#
        }
    }
}

extension PresentationAction {
    var demoBridgeCommand: String? {
        switch self {
        case .nextSlide:
            return "next"
        case .previousSlide:
            return "previous"
        case .zoomIn:
            return "zoomIn"
        case .zoomOut:
            return "zoomOut"
        case .setZoom:
            return nil
        case .setPan:
            return nil
        case .startPresentation:
            return "start"
        case .exitPresentation:
            return "exit"
        case .toggleAnnotation:
            return "toggleAnnotation"
        case .clearAnnotations:
            return "clearAnnotations"
        case .drawAnnotation, .toggleRecording, .none:
            return nil
        }
    }
}

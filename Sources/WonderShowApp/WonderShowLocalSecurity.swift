import CryptoKit
import Foundation
import Security

enum WonderShowLocalSecurity {
    static let headerName = "X-WonderShow-Local-Token"

    static let sharedToken: String = {
        if let existing = ProcessInfo.processInfo.environment["WONDERSHOW_LOCAL_TOKEN"],
           isPlausibleToken(existing) {
            return existing
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return Data(bytes).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }

        let fallback = "\(UUID().uuidString)-\(Date().timeIntervalSince1970)-\(ProcessInfo.processInfo.processIdentifier)"
        return SHA256.hash(data: Data(fallback.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }()

    static func applyTokenEnvironment(to process: Process) {
        process.environment = sidecarEnvironment()
    }

    static func sidecarEnvironment(
        from hostEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let allowedKeys = [
            "PATH",
            "LANG",
            "LC_ALL",
            "LC_CTYPE",
            "SYSTEMROOT",
            "TMPDIR",
        ]
        var environment: [String: String] = [:]
        for key in allowedKeys {
            if let value = hostEnvironment[key] {
                environment[key] = value
            }
        }
        environment["WONDERSHOW_LOCAL_TOKEN"] = sharedToken
        return environment
    }

    static func isAuthorized(_ token: String?) -> Bool {
        guard let token else { return false }
        return constantTimeEquals(token, sharedToken)
    }

    static func tokenQueryValue() -> String {
        sharedToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sharedToken
    }

    private static func isPlausibleToken(_ token: String) -> Bool {
        token.count >= 24 && token.count <= 256
    }

    private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let lhsBytes = Array(lhs.utf8)
        let rhsBytes = Array(rhs.utf8)
        var difference = lhsBytes.count ^ rhsBytes.count
        let maxCount = max(lhsBytes.count, rhsBytes.count)

        for index in 0..<maxCount {
            let lhsByte = index < lhsBytes.count ? lhsBytes[index] : 0
            let rhsByte = index < rhsBytes.count ? rhsBytes[index] : 0
            difference |= Int(lhsByte ^ rhsByte)
        }

        return difference == 0
    }
}

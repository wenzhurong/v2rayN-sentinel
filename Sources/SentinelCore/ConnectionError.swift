import Foundation

public struct ConnectionErrorInfo: Equatable, Sendable {
    public let target: String?
    public let kind: String
    public init(target: String?, kind: String) {
        self.target = target
        self.kind = kind
    }
}

public enum ConnectionErrorParser {
    // dial tcp|udp <host:port>: <reason>   (host:port 中间冒号无空格,reason 前是"冒号+空格")
    private static let dialRegex = try! NSRegularExpression(
        pattern: #"dial (?:tcp|udp) (.+?): (.+)$"#
    )

    public static func extract(from message: String) -> ConnectionErrorInfo {
        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        if let m = dialRegex.firstMatch(in: message, options: [], range: range) {
            func g(_ i: Int) -> String {
                guard let r = Range(m.range(at: i), in: message) else { return "" }
                return String(message[r])
            }
            return ConnectionErrorInfo(target: g(1), kind: g(2).trimmingCharacters(in: .whitespaces))
        }
        return ConnectionErrorInfo(target: nil,
                                   kind: message.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

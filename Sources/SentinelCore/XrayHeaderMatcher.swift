import Foundation

public struct XrayHeaderMatcher: HeaderMatcher {
    public init() {}

    private static let regex = try! NSRegularExpression(
        pattern: #"^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?) \[([A-Za-z]+)\] (.*)$"#
    )

    public func match(_ line: String) -> (String, LogLevel, String)? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let m = XrayHeaderMatcher.regex.firstMatch(in: line, options: [], range: range) else {
            return nil
        }
        func g(_ i: Int) -> String {
            guard let r = Range(m.range(at: i), in: line) else { return "" }
            return String(line[r])
        }
        let level: LogLevel
        switch g(2) {
        case "Debug": level = .debug
        case "Info": level = .info
        case "Warning": level = .warn
        case "Error": level = .error
        default: level = .unknown
        }
        return (g(1), level, g(3))
    }
}

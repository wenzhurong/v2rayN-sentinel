import Foundation

public struct SingboxHeaderMatcher: HeaderMatcher {
    public init() {}

    // <tz> <date> <time> <LEVEL> <message> ;时区 +0530 或 +05:30 皆可。
    private static let regex = try! NSRegularExpression(
        pattern: #"^[+-]\d{2}:?\d{2} (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) ([A-Z]+) (.*)$"#
    )

    public func match(_ line: String) -> (String, LogLevel, String)? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let m = SingboxHeaderMatcher.regex.firstMatch(in: line, options: [], range: range) else {
            return nil
        }
        func g(_ i: Int) -> String {
            guard let r = Range(m.range(at: i), in: line) else { return "" }
            return String(line[r])
        }
        let level: LogLevel
        switch g(2) {
        case "TRACE", "DEBUG": level = .debug
        case "INFO": level = .info
        case "WARN": level = .warn
        case "ERROR": level = .error
        case "FATAL", "PANIC": level = .fatal
        default: level = .unknown
        }
        return (g(1), level, g(3))
    }
}

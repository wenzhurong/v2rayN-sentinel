import Foundation

public protocol HeaderMatcher: Sendable {
    /// 若该行是记录行头,返回 (时间戳, 级别, 正文);否则 nil(续行)。
    func match(_ line: String) -> (String, LogLevel, String)?
}

public struct SerilogHeaderMatcher: HeaderMatcher {
    public init() {}

    private static let regex = try! NSRegularExpression(
        pattern: #"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+)-([A-Za-z]+) ?(.*)$"#
    )

    public func match(_ line: String) -> (String, LogLevel, String)? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let m = SerilogHeaderMatcher.regex.firstMatch(in: line, options: [], range: range) else {
            return nil
        }
        func g(_ i: Int) -> String {
            guard let r = Range(m.range(at: i), in: line) else { return "" }
            return String(line[r])
        }
        let level = LogLevel(rawValue: g(2).uppercased()) ?? .unknown
        return (g(1), level, g(3))
    }
}

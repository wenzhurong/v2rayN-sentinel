import Foundation

public enum SourceKind: Sendable { case gui, singbox, xrayError }

public struct LogSource: Sendable {
    public let kind: SourceKind
    public let filePattern: String
    public let matcher: any HeaderMatcher
    public let aggregates: Bool

    public init(kind: SourceKind, filePattern: String, matcher: any HeaderMatcher, aggregates: Bool) {
        self.kind = kind
        self.filePattern = filePattern
        self.matcher = matcher
        self.aggregates = aggregates
    }

    public static let gui = LogSource(
        kind: .gui, filePattern: #"[0-9]{4}-[0-9]{2}-[0-9]{2}\.txt"#,
        matcher: SerilogHeaderMatcher(), aggregates: false)
    public static let singbox = LogSource(
        kind: .singbox, filePattern: #"sbox_[0-9]{4}-[0-9]{2}-[0-9]{2}\.txt"#,
        matcher: SingboxHeaderMatcher(), aggregates: true)
    public static let xrayError = LogSource(
        kind: .xrayError, filePattern: #"Verror_[0-9]{4}-[0-9]{2}-[0-9]{2}\.txt"#,
        matcher: XrayHeaderMatcher(), aggregates: true)
}

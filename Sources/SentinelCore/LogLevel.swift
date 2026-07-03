public enum LogLevel: String, Sendable {
    case info = "INFO"
    case debug = "DEBUG"
    case warn = "WARN"
    case error = "ERROR"
    case fatal = "FATAL"
    case unknown = "UNKNOWN"

    /// 代表需要关注的错误状态的级别。
    public var isError: Bool { self == .error || self == .fatal }
}

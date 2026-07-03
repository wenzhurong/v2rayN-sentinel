public struct LogRecord: Equatable, Sendable {
    public let timestamp: String
    public let level: LogLevel
    public let message: String
    public let raw: String

    public init(timestamp: String, level: LogLevel, message: String, raw: String) {
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.raw = raw
    }
}

import Foundation

public struct HistoryEntry: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: String
    public let level: LogLevel
    public let message: String
    public let signature: String
    public let classification: Classification
    public var count: Int

    public init(id: UUID = UUID(), timestamp: String, level: LogLevel,
                message: String, signature: String,
                classification: Classification, count: Int = 1) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.signature = signature
        self.classification = classification
        self.count = count
    }
}

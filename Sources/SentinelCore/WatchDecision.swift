import Foundation

public struct ReadPlan: Equatable, Sendable {
    public let startOffset: UInt64
    public let filename: String
    public init(startOffset: UInt64, filename: String) {
        self.startOffset = startOffset
        self.filename = filename
    }
}

public enum WatchDecision {
    public static func plan(previousFile: String?, previousOffset: UInt64,
                            currentFile: String, currentSize: UInt64,
                            startAtEndIfNew: Bool) -> ReadPlan {
        if previousFile != currentFile {
            let start: UInt64 = (previousFile == nil && startAtEndIfNew) ? currentSize : 0
            return ReadPlan(startOffset: start, filename: currentFile)
        }
        if currentSize < previousOffset {
            return ReadPlan(startOffset: 0, filename: currentFile)
        }
        return ReadPlan(startOffset: previousOffset, filename: currentFile)
    }
}

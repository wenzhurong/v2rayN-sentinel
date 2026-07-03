import Foundation

public struct ClassifierRules: Sendable {
    public var noisePatterns: [String]
    public var importantKeywords: [String]

    public init(noisePatterns: [String], importantKeywords: [String]) {
        self.noisePatterns = noisePatterns
        self.importantKeywords = importantKeywords
    }

    public static let defaults = ClassifierRules(
        noisePatterns: [
            #"mihomo#\d+.*non-zero exit code"#,
            #"bash#\d+.*exit code \(127\)"#
        ],
        importantKeywords: []
    )
}

public struct Classifier {
    public let rules: ClassifierRules
    public init(rules: ClassifierRules) { self.rules = rules }

    public func classify(_ record: LogRecord) -> Classification {
        guard record.level.isError else { return .ignored }
        let text = record.raw
        for kw in rules.importantKeywords
        where text.range(of: kw, options: [.regularExpression, .caseInsensitive]) != nil {
            return .important
        }
        for p in rules.noisePatterns
        where text.range(of: p, options: .regularExpression) != nil {
            return .ordinary
        }
        return .important
    }
}

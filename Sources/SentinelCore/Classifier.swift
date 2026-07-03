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
        where Classifier.matches(text, pattern: kw, caseInsensitive: true) {
            return .important
        }
        for p in rules.noisePatterns
        where Classifier.matches(text, pattern: p, caseInsensitive: false) {
            return .ordinary
        }
        return .important
    }

    /// 稳健匹配用户可编辑的规则:
    /// - 空/纯空白规则被忽略(不匹配任何行),避免把所有错误静默降级(加固 #2)。
    /// - 无效正则退回字面量匹配,避免 ICU 对错误正则静默返回 nil 而吞掉规则(加固 #3)。
    static func matches(_ text: String, pattern rawPattern: String, caseInsensitive: Bool) -> Bool {
        let pattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return false }
        let isValidRegex = (try? NSRegularExpression(pattern: pattern)) != nil
        var options: String.CompareOptions = isValidRegex ? [.regularExpression] : []
        if caseInsensitive { options.insert(.caseInsensitive) }
        return text.range(of: pattern, options: options) != nil
    }
}

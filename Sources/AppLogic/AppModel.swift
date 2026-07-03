import Foundation
import Combine
import SentinelCore

@MainActor
public final class AppModel: ObservableObject {
    @Published public var settings: Settings
    @Published public private(set) var history: [HistoryEntry] = []
    @Published public private(set) var monitoring: Bool

    private let alerter: Alerting
    private var classifier: Classifier
    private var deduper: Deduper
    private let historyStore: ErrorHistory

    public init(settings: Settings, alerter: Alerting) {
        self.settings = settings
        self.alerter = alerter
        self.monitoring = settings.monitoringEnabled
        self.classifier = Classifier(rules: ClassifierRules(
            noisePatterns: settings.noisePatterns,
            importantKeywords: settings.importantKeywords))
        self.deduper = Deduper(cooldown: settings.dedupeCooldownSeconds)
        self.historyStore = ErrorHistory(limit: settings.historyLimit)
    }

    /// 处理一条日志记录:分级 → 去重 → 报警 + 记历史。`now` 注入以便测试。
    public func handle(_ record: LogRecord, now: Date) {
        guard monitoring else { return }
        let classification = classifier.classify(record)
        guard classification != .ignored else { return }

        let important = (classification == .important)
        let entry = HistoryEntry(
            timestamp: record.timestamp,
            level: record.level,
            message: record.message,
            signature: Deduper.signature(of: record),
            classification: classification,
            count: 1)

        historyStore.record(entry)
        history = historyStore.entries

        guard deduper.shouldAlert(record, now: now) else { return }

        let autoDismiss: TimeInterval? = important ? nil : settings.ordinaryToastSeconds
        alerter.present(entry: entry, important: important, autoDismiss: autoDismiss)
        if important && settings.soundEnabled {
            alerter.playSound(named: settings.soundName)
        }
    }

    public func toggleMonitoring() {
        monitoring.toggle()
        settings.monitoringEnabled = monitoring
    }

    public func clearHistory() {
        historyStore.clear()
        history = historyStore.entries
    }
}

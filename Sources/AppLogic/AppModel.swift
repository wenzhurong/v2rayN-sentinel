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
    private let aggregator: Aggregator

    public init(settings: Settings, alerter: Alerting) {
        self.settings = settings
        self.alerter = alerter
        self.monitoring = settings.monitoringEnabled
        self.classifier = Classifier(rules: ClassifierRules(
            noisePatterns: settings.noisePatterns,
            importantKeywords: settings.importantKeywords))
        self.deduper = Deduper(cooldown: settings.dedupeCooldownSeconds)
        self.historyStore = ErrorHistory(limit: settings.historyLimit)
        self.aggregator = Aggregator(params: AggregatorParams(
            burstWindow: settings.burstWindowSeconds,
            burstThreshold: settings.burstThreshold,
            escalationCooldown: settings.escalationCooldownSeconds,
            idleReset: settings.aggregatedToastIdleSeconds))
    }

    /// 处理一条日志记录。GUI 源走 v1 路径;内核源经 Aggregator 聚合/突发升级。`now` 注入以便测试。
    public func handle(_ record: LogRecord, source: SourceKind = .gui, now: Date) {
        guard monitoring else { return }
        if source == .gui {
            handleGui(record, now: now)
        } else {
            handleCore(record, now: now)
        }
    }

    // MARK: GUI 源(v1 行为不变)
    private func handleGui(_ record: LogRecord, now: Date) {
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

    // MARK: 内核源(sing-box / xray):聚合 + 突发升级
    private func handleCore(_ record: LogRecord, now: Date) {
        guard settings.coreMonitoringEnabled else { return }
        let isErr = record.level.isError
            || (settings.coreAlertIncludesWarning && record.level == .warn)
        guard isErr else { return }

        let info = ConnectionErrorParser.extract(from: record.message)
        let key = Aggregator.key(for: record)
        let outcome = aggregator.ingest(key: key, now: now)
        let title = info.target.map { "\($0)  \(info.kind)" } ?? record.message

        let entry = HistoryEntry(
            timestamp: record.timestamp, level: record.level, message: title,
            signature: key, classification: .ordinary, count: outcome.count)
        historyStore.record(entry)
        history = historyStore.entries

        alerter.presentAggregated(key: key, title: title, count: outcome.count,
                                  autoDismiss: settings.aggregatedToastIdleSeconds)
        if outcome.escalate {
            let important = HistoryEntry(
                timestamp: record.timestamp, level: record.level,
                message: "持续故障:\(title)(×\(outcome.count))",
                signature: key, classification: .important, count: outcome.count)
            alerter.present(entry: important, important: true, autoDismiss: nil)
            if settings.soundEnabled { alerter.playSound(named: settings.soundName) }
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

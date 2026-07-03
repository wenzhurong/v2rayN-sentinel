public final class ErrorHistory {
    public private(set) var entries: [HistoryEntry] = []
    public let limit: Int

    /// limit 收敛为 >=0,避免负值(损坏/手改配置)导致 record 中 removeLast 越界崩溃(加固 #1)。
    public init(limit: Int) { self.limit = max(0, limit) }

    public func record(_ entry: HistoryEntry) {
        if var first = entries.first, first.signature == entry.signature {
            first.count += 1
            entries[0] = first
        } else {
            entries.insert(entry, at: 0)
            if entries.count > limit {
                entries.removeLast(entries.count - limit)
            }
        }
    }

    public func clear() { entries.removeAll() }
}

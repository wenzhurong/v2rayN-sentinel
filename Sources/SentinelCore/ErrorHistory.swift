public final class ErrorHistory {
    public private(set) var entries: [HistoryEntry] = []
    public let limit: Int

    public init(limit: Int) { self.limit = limit }

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

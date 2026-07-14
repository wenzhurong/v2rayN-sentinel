import Foundation

public final class MultiWatcher {
    public var onRecord: ((LogRecord, SourceKind) -> Void)?
    private var watchers: [LogWatcher] = []

    public init(directory: URL, sources: [LogSource],
                startAtEnd: Bool = true, fileManager: FileManager = .default) {
        for s in sources {
            let w = LogWatcher(directory: directory, startAtEnd: startAtEnd,
                               fileManager: fileManager,
                               filePattern: s.filePattern, headerMatcher: s.matcher)
            let kind = s.kind
            w.onRecord = { [weak self] rec in self?.onRecord?(rec, kind) }
            watchers.append(w)
        }
    }

    public func poll() {
        for w in watchers { w.poll() }
    }
}

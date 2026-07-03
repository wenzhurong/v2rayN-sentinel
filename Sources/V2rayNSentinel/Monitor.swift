import Foundation
import SentinelCore
import AppLogic

/// 承载后台监控接线:持有 LogWatcher,用一个 MainActor 轮询循环每秒 poll 一次,
/// 并把解析出的记录交给 AppModel 处理。替代计划中的 AppDelegate/Timer 接线(Swift 6 更干净)。
@MainActor
final class Monitor {
    private let watcher: LogWatcher
    private let model: AppModel
    private var task: Task<Void, Never>?

    init(model: AppModel, directory: URL) {
        self.model = model
        self.watcher = LogWatcher(directory: directory, startAtEnd: true)
        self.watcher.onRecord = { [weak model] record in
            // poll() 始终在下方的 MainActor 轮询循环里被调用,故此处确定处于主线程。
            MainActor.assumeIsolated {
                model?.handle(record, now: Date())
            }
        }
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.watcher.poll()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

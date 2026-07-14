import Foundation
import SentinelCore
import AppLogic

/// 后台监控接线:用 MultiWatcher 同时盯 GUI / sing-box / xray 三个源,
/// 每秒轮询一次并把记录按 source 交给 AppModel;顺便探测内核日志文件是否存在。
@MainActor
final class Monitor {
    private let watcher: MultiWatcher
    private let model: AppModel
    private let directory: URL
    private let fileManager: FileManager
    private var task: Task<Void, Never>?

    init(model: AppModel, directory: URL, fileManager: FileManager = .default) {
        self.model = model
        self.directory = directory
        self.fileManager = fileManager
        self.watcher = MultiWatcher(directory: directory,
                                    sources: [.gui, .singbox, .xrayError],
                                    startAtEnd: true, fileManager: fileManager)
        self.watcher.onRecord = { [weak model] record, kind in
            // poll() 始终在下方的 MainActor 轮询循环里被调用,故此处确定处于主线程。
            MainActor.assumeIsolated {
                model?.handle(record, source: kind, now: Date())
            }
        }
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.watcher.poll()
                let names = (try? self.fileManager.contentsOfDirectory(atPath: self.directory.path)) ?? []
                let hasCore = names.contains { $0.hasPrefix("sbox_") || $0.hasPrefix("Verror_") }
                self.model.setCoreLoggingDetected(hasCore)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

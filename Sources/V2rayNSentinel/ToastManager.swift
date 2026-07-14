import AppKit
import SwiftUI
import SentinelCore

@MainActor
final class ToastManager {
    private final class Box { weak var window: ToastWindow? }

    private var windows: [ToastWindow] = []
    private var keyedWindows: [String: ToastWindow] = [:]
    private var keyedDismissToken: [String: UUID] = [:]
    private let topMargin: CGFloat = 12
    private let sideMargin: CGFloat = 12
    private let spacing: CGFloat = 8

    func show(entry: HistoryEntry, important: Bool,
              autoDismiss: TimeInterval?, screen: NSScreen) {
        let box = Box()
        let view = ToastView(entry: entry, isImportant: important) { [weak self] in
            if let w = box.window { self?.dismiss(w) }
        }
        let window = ToastWindow(content: view)
        box.window = window
        windows.append(window)
        layout(on: screen)
        window.orderFrontRegardless()

        if let seconds = autoDismiss {
            Task { [weak self, weak window] in
                try? await Task.sleep(for: .seconds(seconds))
                if let w = window { self?.dismiss(w) }
            }
        }
    }

    /// 键控聚合 toast:同 key 有活 toast 就更新计数并重置空闲计时,否则新建。
    func showOrUpdateAggregated(key: String, title: String, count: Int,
                                autoDismiss: TimeInterval?, screen: NSScreen) {
        if let existing = keyedWindows[key] {
            let host = NSHostingView(rootView: AggregatedToastView(title: title, count: count))
            existing.contentView = host
            existing.setContentSize(host.fittingSize)
            layout(on: screen)
        } else {
            let window = ToastWindow(content: AggregatedToastView(title: title, count: count))
            keyedWindows[key] = window
            windows.append(window)
            layout(on: screen)
            window.orderFrontRegardless()
        }
        scheduleKeyedDismiss(key: key, after: autoDismiss)
    }

    func dismissAll() {
        windows.forEach { $0.close() }
        windows.removeAll()
        keyedWindows.removeAll()
        keyedDismissToken.removeAll()
    }

    private func scheduleKeyedDismiss(key: String, after seconds: TimeInterval?) {
        guard let seconds else { return }
        let token = UUID()
        keyedDismissToken[key] = token
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.keyedDismissToken[key] == token else { return }
            if let w = self.keyedWindows[key] {
                w.close()
                self.windows.removeAll { $0 === w }
                self.keyedWindows[key] = nil
                self.keyedDismissToken[key] = nil
                if let screen = w.screen ?? NSScreen.main { self.layout(on: screen) }
            }
        }
    }

    private func dismiss(_ window: ToastWindow) {
        window.close()
        windows.removeAll { $0 === window }
        if let screen = window.screen ?? NSScreen.main {
            layout(on: screen)
        }
    }

    /// 从目标屏左上角(菜单栏下方)向下堆叠。
    private func layout(on screen: NSScreen) {
        let visible = screen.visibleFrame   // 已排除菜单栏
        var y = visible.maxY - topMargin
        for w in windows {
            let h = w.frame.height
            y -= h
            w.setFrameOrigin(NSPoint(x: visible.minX + sideMargin, y: y))
            y -= spacing
        }
    }
}

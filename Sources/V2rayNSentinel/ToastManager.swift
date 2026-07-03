import AppKit
import SentinelCore

@MainActor
final class ToastManager {
    private final class Box { weak var window: ToastWindow? }

    private var windows: [ToastWindow] = []
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

    func dismissAll() {
        windows.forEach { $0.close() }
        windows.removeAll()
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

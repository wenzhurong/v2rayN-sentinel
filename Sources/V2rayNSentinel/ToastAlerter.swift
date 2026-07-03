import AppKit
import SentinelCore
import AppLogic

/// 把 AppModel 的抽象 Alerting 落到具体的 toast 窗口 + 系统声音,并按设置选屏。
@MainActor
final class ToastAlerter: Alerting {
    private let toasts = ToastManager()
    private let sound = SoundPlayer()
    var targetScreen: String = "main"

    private func resolveScreen() -> NSScreen {
        if targetScreen != "main",
           let id = UInt32(targetScreen),
           let match = NSScreen.screens.first(where: {
               ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
           }) {
            return match
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    func present(entry: HistoryEntry, important: Bool, autoDismiss: TimeInterval?) {
        toasts.show(entry: entry, important: important,
                    autoDismiss: autoDismiss, screen: resolveScreen())
    }

    func playSound(named name: String) {
        sound.play(named: name)
    }
}

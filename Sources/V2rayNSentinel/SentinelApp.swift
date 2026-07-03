import SwiftUI
import Foundation
import SentinelCore
import AppLogic

@main
struct SentinelApp: App {
    @StateObject private var model: AppModel
    private let monitor: Monitor

    init() {
        let loaded = SettingsStore().load()
        let alerter = ToastAlerter()
        alerter.targetScreen = loaded.targetScreen
        let model = AppModel(settings: loaded, alerter: alerter)
        _model = StateObject(wrappedValue: model)

        let dir: URL
        if let override = loaded.logDirOverride {
            dir = URL(fileURLWithPath: override)
        } else {
            dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/v2rayN/guiLogs")
        }
        let monitor = Monitor(model: model, directory: dir)
        self.monitor = monitor
        monitor.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.monitoring ? "shield" : "shield.slash")
        }

        // 用 SwiftUI.Settings 场景消歧(与 SentinelCore.Settings 同名)。
        SwiftUI.Settings {
            SettingsView(model: model)
        }
    }
}

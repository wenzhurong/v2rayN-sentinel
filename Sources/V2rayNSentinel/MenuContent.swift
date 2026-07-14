import SwiftUI
import AppKit
import AppLogic

struct MenuContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Button(model.monitoring ? "监控中(点击暂停)" : "已暂停(点击开启)") {
            model.toggleMonitoring()
        }
        if model.settings.coreMonitoringEnabled && !model.coreLoggingDetected {
            Text("内核日志未开启(在 v2rayN 里开启核心日志)")
                .foregroundStyle(.orange)
        }
        Divider()
        if model.history.isEmpty {
            Text("暂无错误").foregroundStyle(.secondary)
        } else {
            ForEach(model.history.prefix(15)) { entry in
                Button("\(entry.timestamp) · \(String(entry.message.prefix(50)))") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.message, forType: .string)
                }
            }
            Button("清空历史") { model.clearHistory() }
        }
        Divider()
        SettingsLink { Text("设置…") }
        Button("退出") { NSApplication.shared.terminate(nil) }
    }
}

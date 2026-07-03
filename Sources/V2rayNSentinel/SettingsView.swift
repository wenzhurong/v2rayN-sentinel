import SwiftUI
import SentinelCore
import AppLogic

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var launchError: String?
    private let store = SettingsStore()

    private let systemSounds = ["Basso", "Blow", "Bottle", "Frog", "Funk",
                                "Glass", "Hero", "Morse", "Ping", "Pop", "Purr",
                                "Sosumi", "Submarine", "Tink"]

    var body: some View {
        Form {
            Section("运行") {
                Toggle("开机自启", isOn: Binding(
                    get: { model.settings.launchAtLogin },
                    set: { setLaunchAtLogin($0) }))
                if let err = launchError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
            Section("报警") {
                Toggle("重要错误播放声音", isOn: bind(\.soundEnabled))
                Picker("提示音", selection: bind(\.soundName)) {
                    ForEach(systemSounds, id: \.self) { Text($0).tag($0) }
                }
                Stepper("普通 toast 停留 \(Int(model.settings.ordinaryToastSeconds)) 秒",
                        value: bind(\.ordinaryToastSeconds), in: 1...30)
                Stepper("同类去重冷却 \(Int(model.settings.dedupeCooldownSeconds)) 秒",
                        value: bind(\.dedupeCooldownSeconds), in: 5...600, step: 5)
            }
            Section("规则(每行一条正则)") {
                Text("降级为普通的噪音:")
                TextEditor(text: linesBinding(\.noisePatterns))
                    .frame(minHeight: 60).font(.system(.caption, design: .monospaced))
                Text("强制升级为重要的关键词:")
                TextEditor(text: linesBinding(\.importantKeywords))
                    .frame(minHeight: 40).font(.system(.caption, design: .monospaced))
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { model.settings.launchAtLogin = LoginItemManager.isEnabled }
    }

    // MARK: 绑定辅助(改动即落盘)
    private func bind<T>(_ keyPath: WritableKeyPath<SentinelCore.Settings, T>) -> Binding<T> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { model.settings[keyPath: keyPath] = $0; store.save(model.settings) })
    }
    private func linesBinding(_ keyPath: WritableKeyPath<SentinelCore.Settings, [String]>) -> Binding<String> {
        Binding(
            get: { model.settings[keyPath: keyPath].joined(separator: "\n") },
            set: {
                model.settings[keyPath: keyPath] = $0
                    .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
                store.save(model.settings)
            })
    }
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemManager.setEnabled(enabled)
            model.settings.launchAtLogin = LoginItemManager.isEnabled
            launchError = nil
            store.save(model.settings)
        } catch {
            launchError = "设置开机自启失败:\(error.localizedDescription)(需在打包后的 .app 中操作)"
        }
    }
}

import Foundation

public final class SettingsStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "sentinel.settings") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> Settings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data)
        else { return .default }
        return decoded
    }

    public func save(_ settings: Settings) {
        let safe = Self.sanitized(settings)
        guard let data = try? JSONEncoder().encode(safe) else { return }
        defaults.set(data, forKey: key)
    }

    /// 把非有限的 Double 字段回退为默认值。JSONEncoder 默认对 NaN/Infinity 抛错,
    /// 若不清洗,整次保存会被 try? 静默吞掉、连带丢失无关字段(加固 #8)。
    static func sanitized(_ settings: Settings) -> Settings {
        var out = settings
        if !out.ordinaryToastSeconds.isFinite {
            out.ordinaryToastSeconds = Settings.default.ordinaryToastSeconds
        }
        if !out.dedupeCooldownSeconds.isFinite {
            out.dedupeCooldownSeconds = Settings.default.dedupeCooldownSeconds
        }
        if !out.burstWindowSeconds.isFinite {
            out.burstWindowSeconds = Settings.default.burstWindowSeconds
        }
        if !out.escalationCooldownSeconds.isFinite {
            out.escalationCooldownSeconds = Settings.default.escalationCooldownSeconds
        }
        if !out.aggregatedToastIdleSeconds.isFinite {
            out.aggregatedToastIdleSeconds = Settings.default.aggregatedToastIdleSeconds
        }
        return out
    }
}

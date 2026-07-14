import Foundation

public struct Settings: Codable, Equatable, Sendable {
    public var monitoringEnabled: Bool
    public var launchAtLogin: Bool
    public var soundEnabled: Bool
    public var soundName: String
    public var ordinaryToastSeconds: Double
    public var dedupeCooldownSeconds: Double
    public var targetScreen: String        // "main" 或 displayID 字符串
    public var noisePatterns: [String]
    public var importantKeywords: [String]
    public var historyLimit: Int
    public var logDirOverride: String?
    // v2:内核监控
    public var coreMonitoringEnabled: Bool
    public var burstWindowSeconds: Double
    public var burstThreshold: Int
    public var escalationCooldownSeconds: Double
    public var coreAlertIncludesWarning: Bool
    public var aggregatedToastIdleSeconds: Double

    public init(monitoringEnabled: Bool, launchAtLogin: Bool, soundEnabled: Bool,
                soundName: String, ordinaryToastSeconds: Double, dedupeCooldownSeconds: Double,
                targetScreen: String, noisePatterns: [String], importantKeywords: [String],
                historyLimit: Int, logDirOverride: String?,
                coreMonitoringEnabled: Bool = true,
                burstWindowSeconds: Double = 30,
                burstThreshold: Int = 20,
                escalationCooldownSeconds: Double = 300,
                coreAlertIncludesWarning: Bool = false,
                aggregatedToastIdleSeconds: Double = 10) {
        self.monitoringEnabled = monitoringEnabled
        self.launchAtLogin = launchAtLogin
        self.soundEnabled = soundEnabled
        self.soundName = soundName
        self.ordinaryToastSeconds = ordinaryToastSeconds
        self.dedupeCooldownSeconds = dedupeCooldownSeconds
        self.targetScreen = targetScreen
        self.noisePatterns = noisePatterns
        self.importantKeywords = importantKeywords
        self.historyLimit = historyLimit
        self.logDirOverride = logDirOverride
        self.coreMonitoringEnabled = coreMonitoringEnabled
        self.burstWindowSeconds = burstWindowSeconds
        self.burstThreshold = burstThreshold
        self.escalationCooldownSeconds = escalationCooldownSeconds
        self.coreAlertIncludesWarning = coreAlertIncludesWarning
        self.aggregatedToastIdleSeconds = aggregatedToastIdleSeconds
    }

    /// 容错解码:缺失字段(如旧版 JSON 无 v2 字段)取默认值,避免升级后设置被整体重置。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings.default
        monitoringEnabled = try c.decodeIfPresent(Bool.self, forKey: .monitoringEnabled) ?? d.monitoringEnabled
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        soundEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? d.soundEnabled
        soundName = try c.decodeIfPresent(String.self, forKey: .soundName) ?? d.soundName
        ordinaryToastSeconds = try c.decodeIfPresent(Double.self, forKey: .ordinaryToastSeconds) ?? d.ordinaryToastSeconds
        dedupeCooldownSeconds = try c.decodeIfPresent(Double.self, forKey: .dedupeCooldownSeconds) ?? d.dedupeCooldownSeconds
        targetScreen = try c.decodeIfPresent(String.self, forKey: .targetScreen) ?? d.targetScreen
        noisePatterns = try c.decodeIfPresent([String].self, forKey: .noisePatterns) ?? d.noisePatterns
        importantKeywords = try c.decodeIfPresent([String].self, forKey: .importantKeywords) ?? d.importantKeywords
        historyLimit = try c.decodeIfPresent(Int.self, forKey: .historyLimit) ?? d.historyLimit
        logDirOverride = try c.decodeIfPresent(String.self, forKey: .logDirOverride) ?? d.logDirOverride
        coreMonitoringEnabled = try c.decodeIfPresent(Bool.self, forKey: .coreMonitoringEnabled) ?? d.coreMonitoringEnabled
        burstWindowSeconds = try c.decodeIfPresent(Double.self, forKey: .burstWindowSeconds) ?? d.burstWindowSeconds
        burstThreshold = try c.decodeIfPresent(Int.self, forKey: .burstThreshold) ?? d.burstThreshold
        escalationCooldownSeconds = try c.decodeIfPresent(Double.self, forKey: .escalationCooldownSeconds) ?? d.escalationCooldownSeconds
        coreAlertIncludesWarning = try c.decodeIfPresent(Bool.self, forKey: .coreAlertIncludesWarning) ?? d.coreAlertIncludesWarning
        aggregatedToastIdleSeconds = try c.decodeIfPresent(Double.self, forKey: .aggregatedToastIdleSeconds) ?? d.aggregatedToastIdleSeconds
    }

    public static let `default` = Settings(
        monitoringEnabled: true,
        launchAtLogin: false,
        soundEnabled: true,
        soundName: "Basso",
        ordinaryToastSeconds: 5,
        dedupeCooldownSeconds: 60,
        targetScreen: "main",
        noisePatterns: ClassifierRules.defaults.noisePatterns,
        importantKeywords: ClassifierRules.defaults.importantKeywords,
        historyLimit: 200,
        logDirOverride: nil
    )
}

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

    public init(monitoringEnabled: Bool, launchAtLogin: Bool, soundEnabled: Bool,
                soundName: String, ordinaryToastSeconds: Double, dedupeCooldownSeconds: Double,
                targetScreen: String, noisePatterns: [String], importantKeywords: [String],
                historyLimit: Int, logDirOverride: String?) {
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

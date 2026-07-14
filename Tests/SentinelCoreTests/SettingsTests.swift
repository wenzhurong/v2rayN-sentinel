import XCTest
@testable import SentinelCore

final class SettingsTests: XCTestCase {
    func testDefaultsMatchSpec() {
        let s = Settings.default
        XCTAssertEqual(s.soundName, "Basso")
        XCTAssertEqual(s.ordinaryToastSeconds, 5)
        XCTAssertEqual(s.dedupeCooldownSeconds, 60)
        XCTAssertEqual(s.historyLimit, 200)
        XCTAssertFalse(s.launchAtLogin)
        XCTAssertTrue(s.monitoringEnabled)
        XCTAssertEqual(s.targetScreen, "main")
    }
    func testRoundTripThroughStore() {
        let defaults = UserDefaults(suiteName: "SentinelTest-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults, key: "settings")
        var s = Settings.default
        s.soundName = "Glass"
        s.launchAtLogin = true
        store.save(s)
        XCTAssertEqual(store.load(), s)
    }
    func testLoadWithoutSavedReturnsDefault() {
        let defaults = UserDefaults(suiteName: "SentinelTest-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults, key: "settings")
        XCTAssertEqual(store.load(), Settings.default)
    }

    // 加固 #8:非有限 Double(NaN/Infinity)会让 JSONEncoder 抛错,
    // 被 try? 吞掉后整次保存丢失(连带无关字段)。加固后应清洗为默认值并成功保存。
    func testNonFiniteDoublesAreSanitizedOnSave() {
        let defaults = UserDefaults(suiteName: "SentinelTest-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults, key: "settings")
        var s = Settings.default
        s.soundName = "Glass"
        s.ordinaryToastSeconds = .nan
        s.dedupeCooldownSeconds = .infinity
        store.save(s)
        let loaded = store.load()
        XCTAssertEqual(loaded.soundName, "Glass")   // 保存未被整体丢弃
        XCTAssertEqual(loaded.ordinaryToastSeconds, Settings.default.ordinaryToastSeconds)
        XCTAssertEqual(loaded.dedupeCooldownSeconds, Settings.default.dedupeCooldownSeconds)
    }

    // v2:新增内核监控字段默认值。
    func testV2DefaultsMatchSpec() {
        let s = Settings.default
        XCTAssertTrue(s.coreMonitoringEnabled)
        XCTAssertEqual(s.burstWindowSeconds, 30)
        XCTAssertEqual(s.burstThreshold, 20)
        XCTAssertEqual(s.escalationCooldownSeconds, 300)
        XCTAssertFalse(s.coreAlertIncludesWarning)
        XCTAssertEqual(s.aggregatedToastIdleSeconds, 10)
    }
    // v2:新的 Double 字段也要清洗非有限值。
    func testSanitizeNewNonFiniteDoubles() {
        let defaults = UserDefaults(suiteName: "SentinelTest-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults, key: "settings")
        var s = Settings.default
        s.burstWindowSeconds = .nan
        s.aggregatedToastIdleSeconds = .infinity
        store.save(s)
        let loaded = store.load()
        XCTAssertEqual(loaded.burstWindowSeconds, Settings.default.burstWindowSeconds)
        XCTAssertEqual(loaded.aggregatedToastIdleSeconds, Settings.default.aggregatedToastIdleSeconds)
    }
    // v2:旧版 JSON(缺 v2 字段)应容错解码,缺失字段取默认。
    func testDecodesLegacyJsonMissingV2Fields() throws {
        let legacy = #"{"monitoringEnabled":true,"launchAtLogin":false,"soundEnabled":true,"soundName":"Glass","ordinaryToastSeconds":5,"dedupeCooldownSeconds":60,"targetScreen":"main","noisePatterns":[],"importantKeywords":[],"historyLimit":200}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(legacy.utf8))
        XCTAssertEqual(s.soundName, "Glass")
        XCTAssertTrue(s.coreMonitoringEnabled)
        XCTAssertEqual(s.burstThreshold, 20)
    }
}

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
}

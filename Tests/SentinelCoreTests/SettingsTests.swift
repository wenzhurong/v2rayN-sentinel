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
}

import XCTest
@testable import SentinelCore

final class LogFileLocatorTests: XCTestCase {
    func testPicksNewestDate() {
        let names = ["2026-06-30.txt", "2026-07-02.txt", "2026-07-01.txt"]
        XCTAssertEqual(LogFileLocator.newestDateFile(in: names), "2026-07-02.txt")
    }
    func testIgnoresNonDateFiles() {
        let names = ["cache.db", "README.md", "2026-07-02.txt", "notes.txt"]
        XCTAssertEqual(LogFileLocator.newestDateFile(in: names), "2026-07-02.txt")
    }
    func testReturnsNilWhenNoDateFiles() {
        XCTAssertNil(LogFileLocator.newestDateFile(in: ["cache.db", "x.txt"]))
    }

    // 加固 #7:`\d` 是 Unicode 数字,会把全角/阿拉伯数字文件名当成日期文件,
    // 且其标量排序高于 ASCII 数字,污染 .max()。收窄为 [0-9] 后应被忽略。
    func testIgnoresNonAsciiDigitFilenames() {
        let fullwidth = "\u{FF12}\u{FF10}\u{FF12}\u{FF16}-\u{FF10}\u{FF17}-\u{FF10}\u{FF11}.txt" // ２０２６-０７-０１
        let names = ["2026-07-02.txt", fullwidth]
        XCTAssertEqual(LogFileLocator.newestDateFile(in: names), "2026-07-02.txt")
    }

    // v2:按任意文件名模式选最新(内核日志带前缀)。
    func testNewestMatchingFilePicksPrefixed() {
        let names = ["sbox_2026-07-12.txt", "sbox_2026-07-13.txt", "2026-07-13.txt", "Vaccess_2026-07-13.txt"]
        XCTAssertEqual(
            LogFileLocator.newestMatchingFile(in: names, pattern: #"sbox_[0-9]{4}-[0-9]{2}-[0-9]{2}\.txt"#),
            "sbox_2026-07-13.txt")
    }
}

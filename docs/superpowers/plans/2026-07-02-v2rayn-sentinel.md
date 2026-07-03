# V2rayN Sentinel 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建一个常驻 macOS 菜单栏应用,实时监控 v2rayN 的 guiLogs 日志,发现 error 分级弹窗报警(全部 error → 左上角小 toast;重要 error → 红色卡片 + 声音 + 手动关闭)。

**Architecture:** Swift Package,分两层:`SentinelCore` 库承载全部纯逻辑(解析、定位、分级、去重、设置、历史、轮询决策)并用 XCTest 覆盖;可执行目标 `V2rayNSentinel` 承载 AppKit/SwiftUI UI(MenuBarExtra、NSPanel toast、设置窗口)。轮询以 1s 定时器驱动 `LogWatcher.poll()`,该方法同步、可确定性测试。最终用脚本把 release 二进制组装成 `LSUIElement` 的 `.app` bundle。

**Tech Stack:** Swift 6 / SwiftPM,AppKit + SwiftUI(MenuBarExtra、NSPanel、NSHostingView),ServiceManagement(SMAppService),XCTest。零第三方依赖。

## Global Constraints

- **平台**:macOS 14.0+(用到 MenuBarExtra、SettingsLink、SMAppService);目标 arch arm64。
- **零第三方依赖**:仅系统框架(Foundation / AppKit / SwiftUI / ServiceManagement / XCTest)。
- **对 v2rayN 零侵入**:只读 `~/Library/Application Support/v2rayN/guiLogs/`,绝不写入或修改 v2rayN 任何文件。
- **App 形态**:纯菜单栏应用,`Info.plist` 中 `LSUIElement = true`,不出现在 Dock。
- **Bundle 标识**:`CFBundleIdentifier = com.wenzhurong.v2rayn-sentinel`,`CFBundleExecutable = V2rayNSentinel`,显示名 `V2rayN Sentinel`。
- **日志格式(逐字来自 spec)**:行头正则 `^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+)-([A-Za-z]+) ?(.*)$`;错误级别 = `ERROR` 或 `FATAL`(大小写不敏感);无行头的行是上一条记录的续行。
- **默认噪音规则(逐字来自 spec)**:`mihomo#\d+.*non-zero exit code`、`bash#\d+.*exit code \(127\)`。
- **默认值(逐字来自 spec)**:应用名 `V2rayN Sentinel`;提示音 `Basso`;普通 toast 停留 5s;去重冷却 60s;历史上限 200;落屏默认主屏;开机自启默认关。

---

### Task 0: 初始化 Swift Package 骨架

**Files:**
- Create: `Package.swift`
- Create: `Sources/SentinelCore/Placeholder.swift`
- Create: `Sources/V2rayNSentinel/main_placeholder.swift`
- Create: `Tests/SentinelCoreTests/SmokeTests.swift`
- Create: `.gitignore`

**Interfaces:**
- Produces: 一个可 `swift build` 和 `swift test` 通过的空工程;库 target `SentinelCore`、可执行 target `V2rayNSentinel`、测试 target `SentinelCoreTests`。

- [ ] **Step 1: 写 Package.swift**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "V2rayNSentinel",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SentinelCore"),
        .executableTarget(
            name: "V2rayNSentinel",
            dependencies: ["SentinelCore"]
        ),
        .testTarget(
            name: "SentinelCoreTests",
            dependencies: ["SentinelCore"]
        ),
    ]
)
```

- [ ] **Step 2: 写占位源文件(让三个 target 都能编译)**

`Sources/SentinelCore/Placeholder.swift`:
```swift
public enum SentinelCore {
    public static let version = "0.1.0"
}
```

`Sources/V2rayNSentinel/main_placeholder.swift`（可执行 target 的顶层代码只允许在 `main.swift`,故用 `@main`）:
```swift
import SentinelCore

@main
struct Placeholder {
    static func main() {
        print("V2rayN Sentinel \(SentinelCore.version)")
    }
}
```

`Tests/SentinelCoreTests/SmokeTests.swift`:
```swift
import XCTest
@testable import SentinelCore

final class SmokeTests: XCTestCase {
    func testVersionExists() {
        XCTAssertEqual(SentinelCore.version, "0.1.0")
    }
}
```

- [ ] **Step 3: 写 .gitignore**

```gitignore
.build/
build/
*.xcodeproj
.DS_Store
```

- [ ] **Step 4: 验证构建与测试**

Run: `swift build && swift test`
Expected: 构建成功;`testVersionExists` PASS。

- [ ] **Step 5: 提交**

```bash
git add Package.swift Sources Tests .gitignore
git commit -m "chore: scaffold SwiftPM project (SentinelCore + app + tests)"
```

---

### Task 1: 日志级别 LogLevel

**Files:**
- Create: `Sources/SentinelCore/LogLevel.swift`
- Test: `Tests/SentinelCoreTests/LogLevelTests.swift`

**Interfaces:**
- Produces: `public enum LogLevel: String { case info, debug, warn, error, fatal, unknown }`,原始值为大写英文(`"INFO"` 等);`public var isError: Bool`(`.error`/`.fatal` 为 true)。

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import SentinelCore

final class LogLevelTests: XCTestCase {
    func testParseKnownLevels() {
        XCTAssertEqual(LogLevel(rawValue: "ERROR"), .error)
        XCTAssertEqual(LogLevel(rawValue: "INFO"), .info)
    }
    func testIsErrorTrueForErrorAndFatal() {
        XCTAssertTrue(LogLevel.error.isError)
        XCTAssertTrue(LogLevel.fatal.isError)
    }
    func testIsErrorFalseForInfoDebugWarn() {
        XCTAssertFalse(LogLevel.info.isError)
        XCTAssertFalse(LogLevel.debug.isError)
        XCTAssertFalse(LogLevel.warn.isError)
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --filter LogLevelTests`
Expected: 编译失败("cannot find 'LogLevel'")。

- [ ] **Step 3: 实现**

```swift
public enum LogLevel: String, Sendable {
    case info = "INFO"
    case debug = "DEBUG"
    case warn = "WARN"
    case error = "ERROR"
    case fatal = "FATAL"
    case unknown = "UNKNOWN"

    /// 代表需要关注的错误状态的级别。
    public var isError: Bool { self == .error || self == .fatal }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --filter LogLevelTests`
Expected: 3 个测试全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add Sources/SentinelCore/LogLevel.swift Tests/SentinelCoreTests/LogLevelTests.swift
git commit -m "feat: add LogLevel with isError classification"
```

---

### Task 2: 日志记录与解析器 LogRecord / LogParser

**Files:**
- Create: `Sources/SentinelCore/LogRecord.swift`
- Create: `Sources/SentinelCore/LogParser.swift`
- Test: `Tests/SentinelCoreTests/LogParserTests.swift`

**Interfaces:**
- Consumes: `LogLevel`。
- Produces:
  - `public struct LogRecord: Equatable, Sendable { let timestamp: String; let level: LogLevel; let message: String; let raw: String }`(`message` 为首行正文 + 续行拼接;`raw` 为完整原文)。
  - `public final class LogParser`:`static func parseHeader(_:) -> (String, LogLevel, String)?`(非行头返回 nil);`func consume(_ line: String) -> LogRecord?`(当新行头到达时返回上一条完成的记录);`func flush() -> LogRecord?`(输出末尾挂起记录)。

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import SentinelCore

final class LogParserTests: XCTestCase {
    func testParseHeaderExtractsFields() {
        let line = "2026-06-25 10:51:33.7293-ERROR CliWrap failed exit code (1)."
        let parsed = LogParser.parseHeader(line)
        XCTAssertEqual(parsed?.0, "2026-06-25 10:51:33.7293")
        XCTAssertEqual(parsed?.1, .error)
        XCTAssertEqual(parsed?.2, "CliWrap failed exit code (1).")
    }

    func testContinuationLineReturnsNilHeader() {
        XCTAssertNil(LogParser.parseHeader("    Standard error:"))
    }

    func testConsumeEmitsPreviousRecordOnNewHeader() {
        let p = LogParser()
        XCTAssertNil(p.consume("2026-07-02 09:00:00.0000-INFO started"))
        let rec = p.consume("2026-07-02 09:00:01.0000-ERROR boom")
        XCTAssertEqual(rec?.level, .info)
        XCTAssertEqual(rec?.message, "started")
    }

    func testMultiLineRecordJoinsContinuations() {
        let p = LogParser()
        _ = p.consume("2026-07-02 09:00:01.0000-ERROR boom")
        XCTAssertNil(p.consume("Standard error:"))
        XCTAssertNil(p.consume("stack line 2"))
        let rec = p.flush()
        XCTAssertEqual(rec?.level, .error)
        XCTAssertEqual(rec?.message, "boom\nStandard error:\nstack line 2")
        XCTAssertEqual(rec?.raw,
            "2026-07-02 09:00:01.0000-ERROR boom\nStandard error:\nstack line 2")
    }

    func testFlushOnEmptyReturnsNil() {
        XCTAssertNil(LogParser().flush())
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --filter LogParserTests`
Expected: 编译失败("cannot find 'LogParser' / 'LogRecord'")。

- [ ] **Step 3: 实现 LogRecord**

`Sources/SentinelCore/LogRecord.swift`:
```swift
public struct LogRecord: Equatable, Sendable {
    public let timestamp: String
    public let level: LogLevel
    public let message: String
    public let raw: String

    public init(timestamp: String, level: LogLevel, message: String, raw: String) {
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.raw = raw
    }
}
```

- [ ] **Step 4: 实现 LogParser**

`Sources/SentinelCore/LogParser.swift`:
```swift
import Foundation

public final class LogParser {
    private struct Pending {
        let timestamp: String
        let level: LogLevel
        let firstMessage: String
        let firstRaw: String
        var extra: [String]
    }

    private var pending: Pending?

    public init() {}

    private static let headerRegex = try! NSRegularExpression(
        pattern: #"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+)-([A-Za-z]+) ?(.*)$"#
    )

    /// 若该行是记录行头,返回 (时间戳, 级别, 正文);否则返回 nil(续行)。
    public static func parseHeader(_ line: String) -> (String, LogLevel, String)? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let m = headerRegex.firstMatch(in: line, options: [], range: range) else {
            return nil
        }
        func group(_ i: Int) -> String {
            guard let r = Range(m.range(at: i), in: line) else { return "" }
            return String(line[r])
        }
        let ts = group(1)
        let level = LogLevel(rawValue: group(2).uppercased()) ?? .unknown
        return (ts, level, group(3))
    }

    /// 喂入一行(不含结尾换行)。若此行开启新记录,返回上一条已完成的记录。
    public func consume(_ line: String) -> LogRecord? {
        if let (ts, level, msg) = LogParser.parseHeader(line) {
            let completed = flush()
            pending = Pending(timestamp: ts, level: level,
                              firstMessage: msg, firstRaw: line, extra: [])
            return completed
        } else {
            pending?.extra.append(line)
            return nil
        }
    }

    /// 输出挂起的记录(流空闲时调用)。
    public func flush() -> LogRecord? {
        guard let p = pending else { return nil }
        pending = nil
        let message = ([p.firstMessage] + p.extra).joined(separator: "\n")
        let raw = ([p.firstRaw] + p.extra).joined(separator: "\n")
        return LogRecord(timestamp: p.timestamp, level: p.level,
                         message: message, raw: raw)
    }
}
```

- [ ] **Step 5: 运行,确认通过**

Run: `swift test --filter LogParserTests`
Expected: 5 个测试全部 PASS。

- [ ] **Step 6: 提交**

```bash
git add Sources/SentinelCore/LogRecord.swift Sources/SentinelCore/LogParser.swift Tests/SentinelCoreTests/LogParserTests.swift
git commit -m "feat: add LogRecord and incremental multi-line LogParser"
```

---

### Task 3: 当天日志文件定位 LogFileLocator

**Files:**
- Create: `Sources/SentinelCore/LogFileLocator.swift`
- Test: `Tests/SentinelCoreTests/LogFileLocatorTests.swift`

**Interfaces:**
- Produces: `public enum LogFileLocator { static func newestDateFile(in filenames: [String]) -> String? }`,匹配 `YYYY-MM-DD.txt`,返回日期最大者(ISO 补零可用字典序比较)。

- [ ] **Step 1: 写失败测试**

```swift
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
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --filter LogFileLocatorTests`
Expected: 编译失败("cannot find 'LogFileLocator'")。

- [ ] **Step 3: 实现**

```swift
import Foundation

public enum LogFileLocator {
    /// 从目录文件名中选出日期最大的 `YYYY-MM-DD.txt`。
    public static func newestDateFile(in filenames: [String]) -> String? {
        let dated = filenames.filter {
            $0.range(of: #"^\d{4}-\d{2}-\d{2}\.txt$"#, options: .regularExpression) != nil
        }
        return dated.max()
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --filter LogFileLocatorTests`
Expected: 3 个测试 PASS。

- [ ] **Step 5: 提交**

```bash
git add Sources/SentinelCore/LogFileLocator.swift Tests/SentinelCoreTests/LogFileLocatorTests.swift
git commit -m "feat: locate newest date-named log file"
```

---

### Task 4: 读取偏移决策 WatchDecision

**Files:**
- Create: `Sources/SentinelCore/WatchDecision.swift`
- Test: `Tests/SentinelCoreTests/WatchDecisionTests.swift`

**Interfaces:**
- Produces:
  - `public struct ReadPlan: Equatable, Sendable { let startOffset: UInt64; let filename: String }`
  - `public enum WatchDecision { static func plan(previousFile: String?, previousOffset: UInt64, currentFile: String, currentSize: UInt64, startAtEndIfNew: Bool) -> ReadPlan }`
- 规则:首次(previousFile == nil)且 startAtEndIfNew → 从 currentSize 起(跳过历史);换文件(跨天)→ 从 0 起;size < previousOffset(截断/轮转)→ 从 0 起;否则 → 从 previousOffset 起。

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import SentinelCore

final class WatchDecisionTests: XCTestCase {
    func testFirstRunStartsAtEndWhenRequested() {
        let plan = WatchDecision.plan(previousFile: nil, previousOffset: 0,
                                      currentFile: "2026-07-02.txt", currentSize: 500,
                                      startAtEndIfNew: true)
        XCTAssertEqual(plan, ReadPlan(startOffset: 500, filename: "2026-07-02.txt"))
    }
    func testFirstRunStartsAtZeroWhenNotSkipping() {
        let plan = WatchDecision.plan(previousFile: nil, previousOffset: 0,
                                      currentFile: "2026-07-02.txt", currentSize: 500,
                                      startAtEndIfNew: false)
        XCTAssertEqual(plan.startOffset, 0)
    }
    func testDayRolloverReadsNewFileFromStart() {
        let plan = WatchDecision.plan(previousFile: "2026-07-02.txt", previousOffset: 500,
                                      currentFile: "2026-07-03.txt", currentSize: 20,
                                      startAtEndIfNew: true)
        XCTAssertEqual(plan, ReadPlan(startOffset: 0, filename: "2026-07-03.txt"))
    }
    func testTruncationResetsToZero() {
        let plan = WatchDecision.plan(previousFile: "2026-07-02.txt", previousOffset: 500,
                                      currentFile: "2026-07-02.txt", currentSize: 100,
                                      startAtEndIfNew: true)
        XCTAssertEqual(plan.startOffset, 0)
    }
    func testNormalAppendContinuesFromOffset() {
        let plan = WatchDecision.plan(previousFile: "2026-07-02.txt", previousOffset: 500,
                                      currentFile: "2026-07-02.txt", currentSize: 800,
                                      startAtEndIfNew: true)
        XCTAssertEqual(plan.startOffset, 500)
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --filter WatchDecisionTests`
Expected: 编译失败("cannot find 'WatchDecision'")。

- [ ] **Step 3: 实现**

```swift
import Foundation

public struct ReadPlan: Equatable, Sendable {
    public let startOffset: UInt64
    public let filename: String
    public init(startOffset: UInt64, filename: String) {
        self.startOffset = startOffset
        self.filename = filename
    }
}

public enum WatchDecision {
    public static func plan(previousFile: String?, previousOffset: UInt64,
                            currentFile: String, currentSize: UInt64,
                            startAtEndIfNew: Bool) -> ReadPlan {
        if previousFile != currentFile {
            let start: UInt64 = (previousFile == nil && startAtEndIfNew) ? currentSize : 0
            return ReadPlan(startOffset: start, filename: currentFile)
        }
        if currentSize < previousOffset {
            return ReadPlan(startOffset: 0, filename: currentFile)
        }
        return ReadPlan(startOffset: previousOffset, filename: currentFile)
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --filter WatchDecisionTests`
Expected: 5 个测试 PASS。

- [ ] **Step 5: 提交**

```bash
git add Sources/SentinelCore/WatchDecision.swift Tests/SentinelCoreTests/WatchDecisionTests.swift
git commit -m "feat: add incremental read/rollover/truncation decision logic"
```

---

### Task 5: 分级器 Classifier

**Files:**
- Create: `Sources/SentinelCore/Classification.swift`
- Create: `Sources/SentinelCore/Classifier.swift`
- Test: `Tests/SentinelCoreTests/ClassifierTests.swift`

**Interfaces:**
- Consumes: `LogRecord`、`LogLevel`。
- Produces:
  - `public enum Classification: Equatable, Sendable { case ignored, ordinary, important }`
  - `public struct ClassifierRules: Sendable { var noisePatterns: [String]; var importantKeywords: [String]; static let defaults: ClassifierRules }`
  - `public struct Classifier { let rules: ClassifierRules; func classify(_ record: LogRecord) -> Classification }`
- 规则:非错误级别 → `.ignored`;命中 importantKeywords(正则,不区分大小写)→ `.important`;命中 noisePatterns(正则)→ `.ordinary`;否则 → `.important`。

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import SentinelCore

final class ClassifierTests: XCTestCase {
    private func record(_ level: LogLevel, _ msg: String) -> LogRecord {
        LogRecord(timestamp: "2026-07-02 09:00:00.0000", level: level, message: msg, raw: msg)
    }

    func testInfoIsIgnored() {
        let c = Classifier(rules: .defaults)
        XCTAssertEqual(c.classify(record(.info, "started")), .ignored)
    }
    func testMihomoNoiseIsOrdinary() {
        let c = Classifier(rules: .defaults)
        let msg = "CliWrap...process (mihomo#2615) returned a non-zero exit code (1)."
        XCTAssertEqual(c.classify(record(.error, msg)), .ordinary)
    }
    func testBash127NoiseIsOrdinary() {
        let c = Classifier(rules: .defaults)
        let msg = "process (bash#1550) returned a non-zero exit code (127)."
        XCTAssertEqual(c.classify(record(.error, msg)), .ordinary)
    }
    func testUnknownErrorIsImportant() {
        let c = Classifier(rules: .defaults)
        XCTAssertEqual(c.classify(record(.error, "core crashed unexpectedly")), .important)
    }
    func testImportantKeywordOverridesNoise() {
        var rules = ClassifierRules.defaults
        rules.importantKeywords = ["panic"]
        let c = Classifier(rules: rules)
        let msg = "process (mihomo#1) non-zero exit code panic"
        XCTAssertEqual(c.classify(record(.error, msg)), .important)
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --filter ClassifierTests`
Expected: 编译失败("cannot find 'Classifier'")。

- [ ] **Step 3: 实现 Classification 与规则/分级器**

`Sources/SentinelCore/Classification.swift`:
```swift
public enum Classification: Equatable, Sendable {
    case ignored    // 非错误,不弹
    case ordinary   // 错误但属噪音 → 小 toast
    case important  // 升级:红色 + 声音 + 手动关闭
}
```

`Sources/SentinelCore/Classifier.swift`:
```swift
import Foundation

public struct ClassifierRules: Sendable {
    public var noisePatterns: [String]
    public var importantKeywords: [String]

    public init(noisePatterns: [String], importantKeywords: [String]) {
        self.noisePatterns = noisePatterns
        self.importantKeywords = importantKeywords
    }

    public static let defaults = ClassifierRules(
        noisePatterns: [
            #"mihomo#\d+.*non-zero exit code"#,
            #"bash#\d+.*exit code \(127\)"#
        ],
        importantKeywords: []
    )
}

public struct Classifier {
    public let rules: ClassifierRules
    public init(rules: ClassifierRules) { self.rules = rules }

    public func classify(_ record: LogRecord) -> Classification {
        guard record.level.isError else { return .ignored }
        let text = record.raw
        for kw in rules.importantKeywords
        where text.range(of: kw, options: [.regularExpression, .caseInsensitive]) != nil {
            return .important
        }
        for p in rules.noisePatterns
        where text.range(of: p, options: .regularExpression) != nil {
            return .ordinary
        }
        return .important
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --filter ClassifierTests`
Expected: 5 个测试 PASS。

- [ ] **Step 5: 提交**

```bash
git add Sources/SentinelCore/Classification.swift Sources/SentinelCore/Classifier.swift Tests/SentinelCoreTests/ClassifierTests.swift
git commit -m "feat: add Classifier with noise/important rules"
```

---

### Task 6: 去重节流 Deduper

**Files:**
- Create: `Sources/SentinelCore/Deduper.swift`
- Test: `Tests/SentinelCoreTests/DeduperTests.swift`

**Interfaces:**
- Consumes: `LogRecord`。
- Produces:
  - `public final class Deduper { init(cooldown: TimeInterval); static func signature(of: LogRecord) -> String; func shouldAlert(_ record: LogRecord, now: Date) -> Bool }`
- signature:对 message 去掉 `#\d+` 进程号后去空白;`shouldAlert`:同签名在冷却窗口内返回 false,否则记录时间并返回 true。`now` 注入以便测试。

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import SentinelCore

final class DeduperTests: XCTestCase {
    private func rec(_ msg: String) -> LogRecord {
        LogRecord(timestamp: "t", level: .error, message: msg, raw: msg)
    }

    func testSignatureStripsProcessIds() {
        let a = Deduper.signature(of: rec("process (mihomo#2615) failed"))
        let b = Deduper.signature(of: rec("process (mihomo#1199) failed"))
        XCTAssertEqual(a, b)
    }
    func testFirstAlertPasses() {
        let d = Deduper(cooldown: 60)
        XCTAssertTrue(d.shouldAlert(rec("boom"), now: Date(timeIntervalSince1970: 0)))
    }
    func testWithinCooldownSuppressed() {
        let d = Deduper(cooldown: 60)
        _ = d.shouldAlert(rec("boom"), now: Date(timeIntervalSince1970: 0))
        XCTAssertFalse(d.shouldAlert(rec("boom"), now: Date(timeIntervalSince1970: 30)))
    }
    func testAfterCooldownPassesAgain() {
        let d = Deduper(cooldown: 60)
        _ = d.shouldAlert(rec("boom"), now: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(d.shouldAlert(rec("boom"), now: Date(timeIntervalSince1970: 61)))
    }
    func testDifferentSignaturesIndependent() {
        let d = Deduper(cooldown: 60)
        _ = d.shouldAlert(rec("boom"), now: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(d.shouldAlert(rec("other"), now: Date(timeIntervalSince1970: 1)))
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --filter DeduperTests`
Expected: 编译失败("cannot find 'Deduper'")。

- [ ] **Step 3: 实现**

```swift
import Foundation

public final class Deduper {
    private var lastSeen: [String: Date] = [:]
    public let cooldown: TimeInterval

    public init(cooldown: TimeInterval) { self.cooldown = cooldown }

    /// 归一化签名:抹掉 `#数字` 进程号,便于同类错误合并。
    public static func signature(of record: LogRecord) -> String {
        let stripped = record.message.replacingOccurrences(
            of: #"#\d+"#, with: "#N", options: .regularExpression)
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 同签名在冷却窗口内返回 false;否则记录并返回 true。
    public func shouldAlert(_ record: LogRecord, now: Date) -> Bool {
        let sig = Deduper.signature(of: record)
        if let last = lastSeen[sig], now.timeIntervalSince(last) < cooldown {
            return false
        }
        lastSeen[sig] = now
        return true
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --filter DeduperTests`
Expected: 5 个测试 PASS。

- [ ] **Step 5: 提交**

```bash
git add Sources/SentinelCore/Deduper.swift Tests/SentinelCoreTests/DeduperTests.swift
git commit -m "feat: add Deduper with normalized signature and cooldown"
```

---

### Task 7: 设置模型与持久化 Settings / SettingsStore

**Files:**
- Create: `Sources/SentinelCore/Settings.swift`
- Create: `Sources/SentinelCore/SettingsStore.swift`
- Test: `Tests/SentinelCoreTests/SettingsTests.swift`

**Interfaces:**
- Consumes: `ClassifierRules.defaults`。
- Produces:
  - `public struct Settings: Codable, Equatable, Sendable`(字段见下),`static let default: Settings`。
  - `public final class SettingsStore { init(defaults: UserDefaults, key: String); func load() -> Settings; func save(_ settings: Settings) }`(JSON 编码存 UserDefaults;无值时返回 `.default`)。

- [ ] **Step 1: 写失败测试**

```swift
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
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --filter SettingsTests`
Expected: 编译失败("cannot find 'Settings' / 'SettingsStore'")。

- [ ] **Step 3: 实现 Settings**

```swift
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
```

- [ ] **Step 4: 实现 SettingsStore**

```swift
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
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
```

- [ ] **Step 5: 运行,确认通过**

Run: `swift test --filter SettingsTests`
Expected: 3 个测试 PASS。

- [ ] **Step 6: 提交**

```bash
git add Sources/SentinelCore/Settings.swift Sources/SentinelCore/SettingsStore.swift Tests/SentinelCoreTests/SettingsTests.swift
git commit -m "feat: add Settings model and UserDefaults-backed store"
```

---

### Task 8: 错误历史 ErrorHistory

**Files:**
- Create: `Sources/SentinelCore/HistoryEntry.swift`
- Create: `Sources/SentinelCore/ErrorHistory.swift`
- Test: `Tests/SentinelCoreTests/ErrorHistoryTests.swift`

**Interfaces:**
- Consumes: `LogLevel`、`Classification`。
- Produces:
  - `public struct HistoryEntry: Equatable, Sendable, Identifiable { let id: UUID; let timestamp: String; let level: LogLevel; let message: String; let signature: String; let classification: Classification; var count: Int }`(`init` 中 `id` 默认 `UUID()`)。
  - `public final class ErrorHistory { init(limit: Int); private(set) var entries: [HistoryEntry]; func record(_ entry: HistoryEntry); func clear() }`。若新条目 `signature` 与最新条目相同则累加 `count`,否则前插并按 `limit` 截断(最新在前)。

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import SentinelCore

final class ErrorHistoryTests: XCTestCase {
    private func entry(_ msg: String, sig: String) -> HistoryEntry {
        HistoryEntry(timestamp: "t", level: .error, message: msg,
                     signature: sig, classification: .important, count: 1)
    }

    func testNewestFirst() {
        let h = ErrorHistory(limit: 10)
        h.record(entry("a", sig: "a"))
        h.record(entry("b", sig: "b"))
        XCTAssertEqual(h.entries.map(\.message), ["b", "a"])
    }
    func testCapsAtLimit() {
        let h = ErrorHistory(limit: 2)
        h.record(entry("a", sig: "a"))
        h.record(entry("b", sig: "b"))
        h.record(entry("c", sig: "c"))
        XCTAssertEqual(h.entries.map(\.message), ["c", "b"])
    }
    func testConsecutiveSameSignatureBumpsCount() {
        let h = ErrorHistory(limit: 10)
        h.record(entry("boom", sig: "s"))
        h.record(entry("boom", sig: "s"))
        XCTAssertEqual(h.entries.count, 1)
        XCTAssertEqual(h.entries.first?.count, 2)
    }
    func testClearEmpties() {
        let h = ErrorHistory(limit: 10)
        h.record(entry("a", sig: "a"))
        h.clear()
        XCTAssertTrue(h.entries.isEmpty)
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --filter ErrorHistoryTests`
Expected: 编译失败("cannot find 'HistoryEntry' / 'ErrorHistory'")。

- [ ] **Step 3: 实现 HistoryEntry**

```swift
import Foundation

public struct HistoryEntry: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: String
    public let level: LogLevel
    public let message: String
    public let signature: String
    public let classification: Classification
    public var count: Int

    public init(id: UUID = UUID(), timestamp: String, level: LogLevel,
                message: String, signature: String,
                classification: Classification, count: Int = 1) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.signature = signature
        self.classification = classification
        self.count = count
    }
}
```

- [ ] **Step 4: 实现 ErrorHistory**

```swift
public final class ErrorHistory {
    public private(set) var entries: [HistoryEntry] = []
    public let limit: Int

    public init(limit: Int) { self.limit = limit }

    public func record(_ entry: HistoryEntry) {
        if var first = entries.first, first.signature == entry.signature {
            first.count += 1
            entries[0] = first
        } else {
            entries.insert(entry, at: 0)
            if entries.count > limit {
                entries.removeLast(entries.count - limit)
            }
        }
    }

    public func clear() { entries.removeAll() }
}
```

- [ ] **Step 5: 运行,确认通过**

Run: `swift test --filter ErrorHistoryTests`
Expected: 4 个测试 PASS。

- [ ] **Step 6: 提交**

```bash
git add Sources/SentinelCore/HistoryEntry.swift Sources/SentinelCore/ErrorHistory.swift Tests/SentinelCoreTests/ErrorHistoryTests.swift
git commit -m "feat: add ErrorHistory ring buffer with dedup counting"
```

---

### Task 9: 文件监控轮询 LogWatcher

**Files:**
- Create: `Sources/SentinelCore/LogWatcher.swift`
- Test: `Tests/SentinelCoreTests/LogWatcherTests.swift`

**Interfaces:**
- Consumes: `LogFileLocator`、`WatchDecision`、`LogParser`、`LogRecord`。
- Produces:
  - `public final class LogWatcher { init(directory: URL, startAtEnd: Bool, fileManager: FileManager); var onRecord: ((LogRecord) -> Void)?; func poll() }`
  - `poll()` 执行一次轮询:定位当天文件 → 按 WatchDecision 定偏移 → 用 FileHandle 读增量 → 按行喂 LogParser → 每条完成记录调用 `onRecord`;当本轮无新数据且无残行时 flush 挂起记录。

- [ ] **Step 1: 写失败测试(用临时目录,poll() 同步可测)**

```swift
import XCTest
@testable import SentinelCore

final class LogWatcherTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("watcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }
    private func write(_ name: String, _ text: String) throws {
        try text.data(using: .utf8)!.write(to: dir.appendingPathComponent(name))
    }
    private func append(_ name: String, _ text: String) throws {
        let url = dir.appendingPathComponent(name)
        let fh = try FileHandle(forWritingTo: url)
        defer { try? fh.close() }
        try fh.seekToEnd()
        try fh.write(contentsOf: text.data(using: .utf8)!)
    }

    func testReadsErrorFromStartWhenNotSkipping() throws {
        try write("2026-07-02.txt",
            "2026-07-02 09:00:00.0000-INFO started\n2026-07-02 09:00:01.0000-ERROR boom\n")
        var got: [LogRecord] = []
        let w = LogWatcher(directory: dir, startAtEnd: false)
        w.onRecord = { got.append($0) }
        w.poll()   // 读取两行:INFO 完成,ERROR 挂起
        w.poll()   // 无新数据 → flush ERROR
        XCTAssertEqual(got.map(\.level), [.info, .error])
        XCTAssertEqual(got.last?.message, "boom")
    }

    func testSkipsHistoryWhenStartAtEnd() throws {
        try write("2026-07-02.txt", "2026-07-02 09:00:00.0000-ERROR old\n")
        var got: [LogRecord] = []
        let w = LogWatcher(directory: dir, startAtEnd: true)
        w.onRecord = { got.append($0) }
        w.poll()   // 从末尾起,忽略旧行
        try append("2026-07-02.txt", "2026-07-02 09:01:00.0000-ERROR fresh\n")
        w.poll()
        w.poll()
        XCTAssertEqual(got.map(\.message), ["fresh"])
    }

    func testDayRolloverPicksNewFile() throws {
        try write("2026-07-02.txt", "2026-07-02 23:59:59.0000-INFO late\n")
        let w = LogWatcher(directory: dir, startAtEnd: true)
        var got: [LogRecord] = []
        w.onRecord = { got.append($0) }
        w.poll()
        try write("2026-07-03.txt", "2026-07-03 00:00:01.0000-ERROR newday\n")
        w.poll()
        w.poll()
        XCTAssertEqual(got.map(\.message), ["newday"])
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --filter LogWatcherTests`
Expected: 编译失败("cannot find 'LogWatcher'")。

- [ ] **Step 3: 实现**

```swift
import Foundation

public final class LogWatcher {
    public var onRecord: ((LogRecord) -> Void)?

    private let directory: URL
    private let startAtEnd: Bool
    private let fileManager: FileManager

    private var currentFile: String?
    private var offset: UInt64 = 0
    private var parser = LogParser()
    private var buffer = Data()   // 跨轮的残行

    public init(directory: URL, startAtEnd: Bool = true,
                fileManager: FileManager = .default) {
        self.directory = directory
        self.startAtEnd = startAtEnd
        self.fileManager = fileManager
    }

    /// 一次轮询周期。定时器每秒调用一次。
    public func poll() {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path),
              let newest = LogFileLocator.newestDateFile(in: names) else { return }
        let fileURL = directory.appendingPathComponent(newest)
        let attrs = (try? fileManager.attributesOfItem(atPath: fileURL.path)) ?? [:]
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0

        let plan = WatchDecision.plan(previousFile: currentFile, previousOffset: offset,
                                      currentFile: newest, currentSize: size,
                                      startAtEndIfNew: startAtEnd)

        if plan.filename != currentFile {
            currentFile = plan.filename
            parser = LogParser()
            buffer.removeAll()
        }

        var data = Data()
        if size > plan.startOffset, let fh = try? FileHandle(forReadingFrom: fileURL) {
            defer { try? fh.close() }
            try? fh.seek(toOffset: plan.startOffset)
            data = (try? fh.readToEnd()) ?? Data()
        }
        offset = size

        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            let line = String(decoding: lineData, as: UTF8.self)
            if let record = parser.consume(line) { onRecord?(record) }
        }

        // 流已空闲:输出挂起记录(如带续行的多行异常已到齐)。
        if data.isEmpty && buffer.isEmpty, let record = parser.flush() {
            onRecord?(record)
        }
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --filter LogWatcherTests`
Expected: 3 个测试 PASS。

- [ ] **Step 5: 全量回归**

Run: `swift test`
Expected: 至此所有 core 测试 PASS。

- [ ] **Step 6: 提交**

```bash
git add Sources/SentinelCore/LogWatcher.swift Tests/SentinelCoreTests/LogWatcherTests.swift
git commit -m "feat: add polling LogWatcher with incremental read and rollover"
```

---

### Task 10: 提示音 SoundPlayer

**Files:**
- Create: `Sources/V2rayNSentinel/SoundPlayer.swift`

**Interfaces:**
- Produces: `final class SoundPlayer { func play(named name: String) }`。找到命名系统音则播放,否则 `NSSound.beep()`。

- [ ] **Step 1: 实现**

```swift
import AppKit

/// 播放命名的系统提示音(如 "Basso");找不到则退回系统 beep。
final class SoundPlayer {
    func play(named name: String) {
        if let sound = NSSound(named: NSSound.Name(name)) {
            sound.stop()
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}
```

- [ ] **Step 2: 验证编译**

Run: `swift build`
Expected: 构建成功。

- [ ] **Step 3: 手动验证(可选)**

在临时 `main` 中调用 `SoundPlayer().play(named: "Basso")` 应听到系统 Basso 音;或留到 Task 17 端到端一并验证。

- [ ] **Step 4: 提交**

```bash
git add Sources/V2rayNSentinel/SoundPlayer.swift
git commit -m "feat: add SoundPlayer wrapping NSSound"
```

---

### Task 11: 开机自启 LoginItemManager

**Files:**
- Create: `Sources/V2rayNSentinel/LoginItemManager.swift`

**Interfaces:**
- Produces: `enum LoginItemManager { static var isEnabled: Bool { get }; static func setEnabled(_ enabled: Bool) throws }`,基于 `SMAppService.mainApp`。
- 注意:`SMAppService` 需在**已打包的 `.app`** 内运行才生效;裸 SPM 二进制下 `register()` 会抛错,由调用方捕获并提示。

- [ ] **Step 1: 实现**

```swift
import ServiceManagement

/// 用现代 SMAppService 管理"登录时启动"。需在打包后的 .app 内生效。
enum LoginItemManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
```

- [ ] **Step 2: 验证编译**

Run: `swift build`
Expected: 构建成功。

- [ ] **Step 3: 提交**

```bash
git add Sources/V2rayNSentinel/LoginItemManager.swift
git commit -m "feat: add LoginItemManager via SMAppService"
```

---

### Task 12: Toast 视图与窗口 ToastView / ToastWindow

**Files:**
- Create: `Sources/V2rayNSentinel/ToastView.swift`
- Create: `Sources/V2rayNSentinel/ToastWindow.swift`

**Interfaces:**
- Consumes: `HistoryEntry`(SentinelCore)。
- Produces:
  - `struct ToastView: View`(入参 `entry: HistoryEntry`、`isImportant: Bool`、`onClose: () -> Void`)。
  - `final class ToastWindow: NSPanel`(`init<Content: View>(content: Content)`;无边框、不激活、`level = .statusBar`、透明背景、随内容自适应尺寸;`canBecomeKey == false`)。

- [ ] **Step 1: 实现 ToastView**

```swift
import SwiftUI
import SentinelCore

struct ToastView: View {
    let entry: HistoryEntry
    let isImportant: Bool
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.timestamp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.message)
                    .font(.callout)
                    .lineLimit(isImportant ? 6 : 2)
                    .foregroundStyle(isImportant ? Color.red : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if isImportant {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: isImportant ? 420 : 360, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isImportant ? Color.red : Color.clear, lineWidth: 2)
        )
    }
}
```

- [ ] **Step 2: 实现 ToastWindow**

```swift
import AppKit
import SwiftUI

/// 承载 SwiftUI toast 的无边框浮动面板,置于菜单栏层级,不抢焦点。
final class ToastWindow: NSPanel {
    init<Content: View>(content: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false

        let host = NSHostingView(rootView: content)
        let size = host.fittingSize
        setContentSize(size)
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
```

- [ ] **Step 3: 验证编译**

Run: `swift build`
Expected: 构建成功。

- [ ] **Step 4: 提交**

```bash
git add Sources/V2rayNSentinel/ToastView.swift Sources/V2rayNSentinel/ToastWindow.swift
git commit -m "feat: add ToastView and floating ToastWindow (NSPanel)"
```

---

### Task 13: Toast 管理与定位 ToastManager

**Files:**
- Create: `Sources/V2rayNSentinel/ToastManager.swift`

**Interfaces:**
- Consumes: `HistoryEntry`、`ToastView`、`ToastWindow`。
- Produces: `@MainActor final class ToastManager { func show(entry: HistoryEntry, important: Bool, autoDismiss: TimeInterval?, screen: NSScreen); func dismissAll() }`。窗口从目标屏左上角向下堆叠;普通 toast 到时淡出关闭,重要 toast 由 `onClose` 手动关闭;关闭后重新布局。

- [ ] **Step 1: 实现**

```swift
import AppKit
import SentinelCore

@MainActor
final class ToastManager {
    private final class Box { weak var window: ToastWindow? }

    private var windows: [ToastWindow] = []
    private let topMargin: CGFloat = 12
    private let sideMargin: CGFloat = 12
    private let spacing: CGFloat = 8

    func show(entry: HistoryEntry, important: Bool,
              autoDismiss: TimeInterval?, screen: NSScreen) {
        let box = Box()
        let view = ToastView(entry: entry, isImportant: important) { [weak self] in
            if let w = box.window { self?.dismiss(w) }
        }
        let window = ToastWindow(content: view)
        box.window = window
        windows.append(window)
        layout(on: screen)
        window.orderFrontRegardless()

        if let seconds = autoDismiss {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self, weak window] in
                if let w = window { self?.dismiss(w) }
            }
        }
    }

    func dismissAll() {
        windows.forEach { $0.close() }
        windows.removeAll()
    }

    private func dismiss(_ window: ToastWindow) {
        window.close()
        windows.removeAll { $0 === window }
        if let screen = window.screen ?? NSScreen.main { layout(on: screen) }
    }

    /// 从目标屏左上角(菜单栏下方)向下堆叠。
    private func layout(on screen: NSScreen) {
        let visible = screen.visibleFrame   // 已排除菜单栏
        var y = visible.maxY - topMargin
        for w in windows {
            let h = w.frame.height
            y -= h
            w.setFrameOrigin(NSPoint(x: visible.minX + sideMargin, y: y))
            y -= spacing
        }
    }
}
```

- [ ] **Step 2: 验证编译**

Run: `swift build`
Expected: 构建成功。

- [ ] **Step 3: 提交**

```bash
git add Sources/V2rayNSentinel/ToastManager.swift
git commit -m "feat: add ToastManager with top-left stacking and dismissal"
```

---

### Task 14: 协调器 AppModel

**Files:**
- Create: `Sources/V2rayNSentinel/Alerting.swift`
- Create: `Sources/V2rayNSentinel/AppModel.swift`
- Test: `Tests/SentinelCoreTests/` 不适用(App target 逻辑)——本任务测试放入新 target,见 Step 1。
- Create: `Tests/AppLogicTests/AppModelTests.swift`
- Modify: `Package.swift`(新增 `AppLogic` 库 target 承载可测协调逻辑 + 其测试 target)

**Interfaces:**
- Consumes: `SentinelCore`(Classifier、Deduper、ErrorHistory、Settings、LogRecord、HistoryEntry、Classification)。
- Produces:
  - `protocol Alerting: AnyObject { func present(entry: HistoryEntry, important: Bool, autoDismiss: TimeInterval?); func playSound(named name: String) }`
  - `@MainActor final class AppModel: ObservableObject`,含 `func handle(_ record: LogRecord, now: Date)` 供测试直接驱动;`@Published var history: [HistoryEntry]`、`@Published var monitoring: Bool`、`@Published var settings: Settings`;`func toggleMonitoring()`、`func clearHistory()`。
- 说明:为让协调逻辑可单测且不牵扯 AppKit,`Alerting` 抽象出弹窗/声音;`AppModel` 依赖注入 `Alerting`、`Classifier`、`Deduper`、`ErrorHistory`。生产环境用 `ToastManager`+`SoundPlayer` 适配 `Alerting`(在 Task 15 组装)。

> 结构决定:把 `AppModel`、`Alerting` 及协调逻辑放到独立库 target `AppLogic`(依赖 `SentinelCore`),这样 `AppModelTests` 能 `@testable import AppLogic` 而不必链接 UI 可执行体。UI 适配器(Task 15)与 `AppLogic` 一起被可执行 target 依赖。

- [ ] **Step 1: 调整 Package.swift 增加 AppLogic 及其测试**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "V2rayNSentinel",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SentinelCore"),
        .target(name: "AppLogic", dependencies: ["SentinelCore"]),
        .executableTarget(
            name: "V2rayNSentinel",
            dependencies: ["SentinelCore", "AppLogic"]
        ),
        .testTarget(name: "SentinelCoreTests", dependencies: ["SentinelCore"]),
        .testTarget(name: "AppLogicTests", dependencies: ["AppLogic"]),
    ]
)
```

将 `SoundPlayer.swift`、`LoginItemManager.swift`、`ToastView.swift`、`ToastWindow.swift`、`ToastManager.swift` 保留在 `Sources/V2rayNSentinel/`(它们依赖 AppKit,属 UI 层)。新协调逻辑放 `Sources/AppLogic/`。

- [ ] **Step 2: 写失败测试**

`Tests/AppLogicTests/AppModelTests.swift`:
```swift
import XCTest
@testable import AppLogic
import SentinelCore

@MainActor
final class AppModelTests: XCTestCase {
    final class SpyAlerter: Alerting {
        var presented: [(HistoryEntry, Bool)] = []
        var sounds: [String] = []
        func present(entry: HistoryEntry, important: Bool, autoDismiss: TimeInterval?) {
            presented.append((entry, important))
        }
        func playSound(named name: String) { sounds.append(name) }
    }

    private func record(_ level: LogLevel, _ msg: String) -> LogRecord {
        LogRecord(timestamp: "2026-07-02 09:00:00.0000", level: level, message: msg, raw: msg)
    }

    private func makeModel(_ spy: SpyAlerter) -> AppModel {
        AppModel(settings: .default, alerter: spy)
    }

    func testInfoRecordDoesNothing() {
        let spy = SpyAlerter()
        let m = makeModel(spy)
        m.handle(record(.info, "started"), now: Date())
        XCTAssertTrue(spy.presented.isEmpty)
        XCTAssertTrue(m.history.isEmpty)
    }

    func testOrdinaryErrorShowsSmallToastNoSound() {
        let spy = SpyAlerter()
        let m = makeModel(spy)
        m.handle(record(.error, "process (mihomo#1) non-zero exit code (1)"), now: Date())
        XCTAssertEqual(spy.presented.count, 1)
        XCTAssertEqual(spy.presented.first?.1, false)   // important == false
        XCTAssertTrue(spy.sounds.isEmpty)
        XCTAssertEqual(m.history.count, 1)
    }

    func testImportantErrorShowsRedToastWithSound() {
        let spy = SpyAlerter()
        let m = makeModel(spy)
        m.handle(record(.error, "core crashed"), now: Date())
        XCTAssertEqual(spy.presented.first?.1, true)    // important == true
        XCTAssertEqual(spy.sounds, ["Basso"])
    }

    func testDuplicateWithinCooldownSuppressesAlertButCountsHistory() {
        let spy = SpyAlerter()
        let m = makeModel(spy)
        let t0 = Date(timeIntervalSince1970: 0)
        m.handle(record(.error, "core crashed"), now: t0)
        m.handle(record(.error, "core crashed"), now: t0.addingTimeInterval(10))
        XCTAssertEqual(spy.presented.count, 1)          // 第二次被冷却抑制
        XCTAssertEqual(m.history.first?.count, 2)       // 历史累加计数
    }

    func testPausedMonitoringIgnoresRecords() {
        let spy = SpyAlerter()
        let m = makeModel(spy)
        m.toggleMonitoring()                             // 暂停
        m.handle(record(.error, "core crashed"), now: Date())
        XCTAssertTrue(spy.presented.isEmpty)
        XCTAssertTrue(m.history.isEmpty)
    }
}
```

- [ ] **Step 3: 运行,确认失败**

Run: `swift test --filter AppModelTests`
Expected: 编译失败("cannot find 'AppModel' / 'Alerting'")。

- [ ] **Step 4: 实现 Alerting 协议**

`Sources/AppLogic/Alerting.swift`:
```swift
import Foundation
import SentinelCore

/// 弹窗/声音的抽象,便于协调逻辑单测。
@MainActor
public protocol Alerting: AnyObject {
    func present(entry: HistoryEntry, important: Bool, autoDismiss: TimeInterval?)
    func playSound(named name: String)
}
```

- [ ] **Step 5: 实现 AppModel**

`Sources/AppLogic/AppModel.swift`:
```swift
import Foundation
import SwiftUI
import SentinelCore

@MainActor
public final class AppModel: ObservableObject {
    @Published public var settings: Settings
    @Published public private(set) var history: [HistoryEntry] = []
    @Published public private(set) var monitoring: Bool

    private let alerter: Alerting
    private var classifier: Classifier
    private var deduper: Deduper
    private let historyStore: ErrorHistory

    public init(settings: Settings, alerter: Alerting) {
        self.settings = settings
        self.alerter = alerter
        self.monitoring = settings.monitoringEnabled
        self.classifier = Classifier(rules: ClassifierRules(
            noisePatterns: settings.noisePatterns,
            importantKeywords: settings.importantKeywords))
        self.deduper = Deduper(cooldown: settings.dedupeCooldownSeconds)
        self.historyStore = ErrorHistory(limit: settings.historyLimit)
    }

    /// 处理一条日志记录:分级 → 去重 → 报警 + 记历史。`now` 注入以便测试。
    public func handle(_ record: LogRecord, now: Date) {
        guard monitoring else { return }
        let classification = classifier.classify(record)
        guard classification != .ignored else { return }

        let important = (classification == .important)
        let entry = HistoryEntry(
            timestamp: record.timestamp,
            level: record.level,
            message: record.message,
            signature: Deduper.signature(of: record),
            classification: classification,
            count: 1)

        historyStore.record(entry)
        history = historyStore.entries

        guard deduper.shouldAlert(record, now: now) else { return }

        let autoDismiss: TimeInterval? = important ? nil : settings.ordinaryToastSeconds
        alerter.present(entry: entry, important: important, autoDismiss: autoDismiss)
        if important && settings.soundEnabled {
            alerter.playSound(named: settings.soundName)
        }
    }

    public func toggleMonitoring() {
        monitoring.toggle()
        settings.monitoringEnabled = monitoring
    }

    public func clearHistory() {
        historyStore.clear()
        history = historyStore.entries
    }
}
```

- [ ] **Step 6: 运行,确认通过**

Run: `swift test --filter AppModelTests`
Expected: 5 个测试 PASS。

- [ ] **Step 7: 全量回归**

Run: `swift test`
Expected: 全部 PASS。

- [ ] **Step 8: 提交**

```bash
git add Package.swift Sources/AppLogic Tests/AppLogicTests
git commit -m "feat: add AppModel coordinator with injectable Alerting"
```

---

### Task 15: 应用入口与菜单 SentinelApp / MenuContent / 报警适配器

**Files:**
- Create: `Sources/V2rayNSentinel/ToastAlerter.swift`
- Create: `Sources/V2rayNSentinel/MenuContent.swift`
- Create: `Sources/V2rayNSentinel/SentinelApp.swift`
- Delete: `Sources/V2rayNSentinel/main_placeholder.swift`

**Interfaces:**
- Consumes: `AppModel`、`Alerting`、`ToastManager`、`SoundPlayer`、`HistoryEntry`。
- Produces:
  - `final class ToastAlerter: Alerting`(把 `present`/`playSound` 落到 `ToastManager` + `SoundPlayer`,并按 `settings.targetScreen` 选屏)。
  - `struct MenuContent: View`(菜单栏下拉:监控开关、最近错误、清空、设置、退出)。
  - `@main struct SentinelApp: App`(`MenuBarExtra` + `Settings` 场景;启动 1s 定时器驱动 `LogWatcher.poll()`;把记录送 `AppModel.handle(_:now:)`)。

- [ ] **Step 1: 实现 ToastAlerter**

```swift
import AppKit
import SentinelCore
import AppLogic

@MainActor
final class ToastAlerter: Alerting {
    private let toasts = ToastManager()
    private let sound = SoundPlayer()
    var targetScreen: String = "main"

    private func resolveScreen() -> NSScreen {
        if targetScreen != "main",
           let id = UInt32(targetScreen),
           let match = NSScreen.screens.first(where: {
               ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
           }) {
            return match
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    func present(entry: HistoryEntry, important: Bool, autoDismiss: TimeInterval?) {
        toasts.show(entry: entry, important: important,
                    autoDismiss: autoDismiss, screen: resolveScreen())
    }

    func playSound(named name: String) {
        sound.play(named: name)
    }
}
```

- [ ] **Step 2: 实现 MenuContent**

```swift
import SwiftUI
import AppLogic

struct MenuContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Button(model.monitoring ? "监控中(点击暂停)" : "已暂停(点击开启)") {
            model.toggleMonitoring()
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
```

- [ ] **Step 3: 实现 SentinelApp(入口 + 定时器接线)**

```swift
import SwiftUI
import Foundation
import SentinelCore
import AppLogic

@main
struct SentinelApp: App {
    @StateObject private var model: AppModel
    private let watcher: LogWatcher
    private let alerter: ToastAlerter
    @State private var timer: Timer?

    init() {
        let settings = SettingsStore().load()
        let alerter = ToastAlerter()
        alerter.targetScreen = settings.targetScreen
        let model = AppModel(settings: settings, alerter: alerter)

        let dir: URL
        if let override = settings.logDirOverride {
            dir = URL(fileURLWithPath: override)
        } else {
            dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/v2rayN/guiLogs")
        }
        let watcher = LogWatcher(directory: dir, startAtEnd: true)

        _model = StateObject(wrappedValue: model)
        self.watcher = watcher
        self.alerter = alerter

        // 记录回调:交给协调器(用当前时间去重)。
        watcher.onRecord = { [weak model] record in
            Task { @MainActor in model?.handle(record, now: Date()) }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.monitoring ? "shield" : "shield.slash")
        }

        Settings {
            SettingsView(model: model)
                .onChange(of: model.settings.targetScreen) { _, new in
                    alerter.targetScreen = new
                }
        }
        .onChange(of: model.monitoring) { _, _ in }   // 占位:保持 model 被观察
    }
}
```

> 注:定时器在 App 生命周期内启动。由于 `App.init` 不便持有 RunLoop 定时器句柄,改为在 `MenuContent.onAppear` 或专用 `AppDelegate` 启动。为稳妥,采用 AppDelegate,见 Step 4。

- [ ] **Step 4: 用 AppDelegate 承载轮询定时器(替换 Step 3 中的定时器占位)**

在 `SentinelApp.swift` 顶部补充,并在 `SentinelApp` 中用 `@NSApplicationDelegateAdaptor`:
```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onTick: (() -> Void)?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.onTick?()
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }
}
```
并在 `SentinelApp` 中:
```swift
@NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
```
在 `init()` 末尾把 tick 接到 watcher:
```swift
// 放在 init 结尾
let w = watcher
appDelegate.onTick = { w.poll() }
```
> 若 `@NSApplicationDelegateAdaptor` 在 `init` 中尚不可用,改为在 `applicationDidFinishLaunching` 里持有 watcher 并直接 `poll()`;两种接线取其一,保证每秒调用 `watcher.poll()` 且 `onRecord` 已设置。

- [ ] **Step 5: 删除占位入口**

```bash
git rm Sources/V2rayNSentinel/main_placeholder.swift
```

- [ ] **Step 6: 验证编译**

Run: `swift build`
Expected: 构建成功(此时 `SettingsView` 尚未创建 → 若报缺失,先做 Task 16 再回来构建;两任务合并提交亦可)。

- [ ] **Step 7: 提交**

```bash
git add Sources/V2rayNSentinel/ToastAlerter.swift Sources/V2rayNSentinel/MenuContent.swift Sources/V2rayNSentinel/SentinelApp.swift
git commit -m "feat: add app entry, menu bar content, and toast alerter"
```

---

### Task 16: 设置界面 SettingsView

**Files:**
- Create: `Sources/V2rayNSentinel/SettingsView.swift`

**Interfaces:**
- Consumes: `AppModel`、`Settings`、`LoginItemManager`。
- Produces: `struct SettingsView: View`,绑定 `model.settings` 的各开关;开机自启开关调用 `LoginItemManager.setEnabled(_:)` 并回读 `isEnabled`;所有改动通过 `SettingsStore().save(_:)` 落盘。

- [ ] **Step 1: 实现**

```swift
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
    private func bind<T>(_ keyPath: WritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { model.settings[keyPath: keyPath] = $0; store.save(model.settings) })
    }
    private func linesBinding(_ keyPath: WritableKeyPath<Settings, [String]>) -> Binding<String> {
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
```

- [ ] **Step 2: 验证编译(App 完整)**

Run: `swift build`
Expected: 构建成功。

- [ ] **Step 3: 全量回归**

Run: `swift test`
Expected: 全部 PASS。

- [ ] **Step 4: 提交**

```bash
git add Sources/V2rayNSentinel/SettingsView.swift
git commit -m "feat: add SettingsView with persisted preferences and login-item toggle"
```

---

### Task 17: 打包成 .app 并端到端验证

**Files:**
- Create: `Resources/Info.plist`
- Create: `scripts/make-app.sh`
- Create: `scripts/feed-log.sh`

**Interfaces:**
- Produces:
  - `Info.plist`(LSUIElement、bundle id、可执行名、最低系统版本)。
  - `make-app.sh`:release 构建 + 组装 `build/V2rayN Sentinel.app`。
  - `feed-log.sh`:向指定目录按 v2rayN 格式追加测试日志行,用于手动验证。

- [ ] **Step 1: 写 Info.plist**

`Resources/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>V2rayN Sentinel</string>
    <key>CFBundleDisplayName</key>     <string>V2rayN Sentinel</string>
    <key>CFBundleIdentifier</key>      <string>com.wenzhurong.v2rayn-sentinel</string>
    <key>CFBundleExecutable</key>      <string>V2rayNSentinel</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHumanReadableCopyright</key> <string>© 2026 wenzhurong</string>
</dict>
</plist>
```

- [ ] **Step 2: 写 make-app.sh**

`scripts/make-app.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="V2rayN Sentinel"
EXECUTABLE="V2rayNSentinel"

echo "==> Building release binary…"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/$EXECUTABLE"

DEST="build/$APP_NAME.app"
echo "==> Assembling $DEST…"
rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"
cp "$BIN_PATH" "$DEST/Contents/MacOS/$EXECUTABLE"
cp Resources/Info.plist "$DEST/Contents/Info.plist"

echo "==> Done: $DEST"
echo "    运行: open \"$DEST\""
```

- [ ] **Step 3: 写 feed-log.sh(手动验证用日志喂食器)**

`scripts/feed-log.sh`:
```bash
#!/usr/bin/env bash
# 用法: ./scripts/feed-log.sh <目标目录> [important|ordinary]
# 向 <目标目录>/<今天>.txt 追加一条测试日志行。
set -euo pipefail
DIR="${1:?需要目标目录}"
KIND="${2:-important}"
mkdir -p "$DIR"
TODAY="$(date +%Y-%m-%d)"
TS="$(date '+%Y-%m-%d %H:%M:%S.0000')"
if [ "$KIND" = "ordinary" ]; then
  LINE="$TS-ERROR process (mihomo#$RANDOM) returned a non-zero exit code (1)."
else
  LINE="$TS-ERROR test core crashed unexpectedly [$RANDOM]"
fi
echo "$LINE" >> "$DIR/$TODAY.txt"
echo "已写入: $LINE"
```

- [ ] **Step 4: 赋可执行权限并打包**

Run:
```bash
chmod +x scripts/make-app.sh scripts/feed-log.sh
./scripts/make-app.sh
```
Expected: 生成 `build/V2rayN Sentinel.app`。

- [ ] **Step 5: 端到端手动验证(临时日志目录,不碰真日志)**

Run:
```bash
# 1) 用一个临时目录当日志源
TESTDIR="$(mktemp -d)"
# 2) 让 App 指向该目录:临时写入偏好(bundle id 对应的 domain)
defaults write com.wenzhurong.v2rayn-sentinel sentinel.settings -data \
  "$(python3 -c 'import json,sys; print(json.dumps({"monitoringEnabled":True,"launchAtLogin":False,"soundEnabled":True,"soundName":"Basso","ordinaryToastSeconds":5,"dedupeCooldownSeconds":60,"targetScreen":"main","noisePatterns":["mihomo#\\d+.*non-zero exit code","bash#\\d+.*exit code \\(127\\)"],"importantKeywords":[],"historyLimit":200,"logDirOverride":sys.argv[1]}).encode().hex())' "$TESTDIR" | python3 -c 'import sys;print(sys.stdin.read())')" 2>/dev/null || true
# 注:上面 defaults 写入较繁琐;更简单的方式是先启动 App,在“设置”里没有该项时,
#     直接改用带 logDirOverride 的调试:见下方“简化验证”。
open "build/V2rayN Sentinel.app"
```

**简化验证(推荐)**:临时把默认日志目录指向测试目录不方便时,直接对真实 guiLogs 触发一次安全的测试写入也可,但为零侵入,推荐:
1. 在 `SentinelApp.init` 里临时把 `dir` 硬编码为 `TESTDIR`(仅调试,验证后还原),重新 `./scripts/make-app.sh` 并 `open`。
2. 制造普通错误:`./scripts/feed-log.sh "$TESTDIR" ordinary` → 预期**左上角小 toast**、5s 后消失、无声音。
3. 制造重要错误:`./scripts/feed-log.sh "$TESTDIR" important` → 预期**左上角红色卡片 + Basso 声音 + 需点 ✕ 关闭**。
4. 点菜单栏盾牌图标 → 见"监控中/暂停"、最近错误列表、设置、退出。
5. 打开"设置" → 切换开机自启(打包后应无报错)、改提示音、改停留秒数,重启 App 后设置保留。
6. 验证完还原调试硬编码,重新打包。

Expected: 上述行为逐条符合;`swift test` 保持全绿。

- [ ] **Step 6: 提交**

```bash
git add Resources/Info.plist scripts/make-app.sh scripts/feed-log.sh
git commit -m "build: add app bundling script, Info.plist, and log feeder for E2E"
```

---

## 自检(Self-Review)

**1. Spec 覆盖对照**
- F1 全部 error 左上角小 toast → Task 12/13(ToastView/Manager 非重要分支)+ Task 14(ordinary 分支,autoDismiss=秒数)✅
- F2 重要 error 红色+声音+手动关闭 → Task 12(红色样式/✕)+ Task 14(important 分支,autoDismiss=nil、播放声音)✅
- F3 重要判定(非噪音即重要,可编辑)→ Task 5(Classifier)+ Task 16(规则编辑)✅
- F4 正经应用形态(菜单栏/历史/设置)→ Task 15/16 ✅
- F5 运行方式可选(开机自启/手动)→ Task 11 + Task 16 ✅
- 监控入口 guiLogs / 增量 / 跨天 / 截断 / 启动定位末尾 → Task 4 + Task 9 ✅
- 去重 60s → Task 6 + Task 14 ✅
- 历史留底可查全文 → Task 8 + Task 15(点条目复制全文)✅
- 多显示器落屏 → Task 15(ToastAlerter.resolveScreen)✅
- 默认值(Basso/5s/60s/200/主屏/自启关)→ Task 7 ✅
- 打包 LSUIElement .app → Task 17 ✅
- 非目标(xray 连接日志)→ 未纳入,符合 spec v1 范围 ✅

**2. 占位扫描**:无 TBD/TODO;所有代码步骤含完整可编译代码;手动验证步骤给出具体命令与预期。Task 15 Step 3/4 对定时器接线给了两种确定性方案,非占位。

**3. 类型一致性**:`LogRecord`/`LogLevel`/`Classification`/`HistoryEntry`/`Settings`/`ClassifierRules` 字段与方法签名在各任务间一致;`Classifier.classify`、`Deduper.shouldAlert(_:now:)`、`ErrorHistory.record`、`AppModel.handle(_:now:)`、`Alerting.present/playSound`、`ToastManager.show`、`LogWatcher.poll/onRecord` 各处调用与定义匹配。`ClassifierRules.defaults.importantKeywords`(Task 5)被 `Settings.default`(Task 7)引用,已一致。

**已知取舍**:Task 15 的 SwiftUI 生命周期定时器接线在不同 macOS 小版本上可能需在 AppDelegate 与 App.init 间二选一,计划已显式给出兜底路径;`LoginItemManager` 仅在打包 `.app` 内生效,已在 Task 11/16/17 标注。

---

## 健壮性加固记录(2026-07-03,Task 3–9 实现后)

对 Task 3–9 的 SentinelCore 逻辑做了一轮对抗式健壮性审查(多子代理并行、实测复现),对确认的缺陷逐条补"先复现的失败测试 + 修复"。全部走 TDD,加固后全量 45 个测试通过。

**已修复(#1–8):**

| # | 位置 | 缺陷 | 修复 | 新增测试 |
|---|---|---|---|---|
| 1 | ErrorHistory | 负 `limit` → 首条 `record` 的 `removeLast` 越界 `fatalError` 崩溃 | init 里 `limit = max(0, limit)` | `testNegativeLimitDoesNotCrash` |
| 2 | Classifier | 空/纯空白噪音规则匹配所有行 → 所有重要错误被静默降级 | `matches()` 忽略空/空白规则 | `testEmptyOrWhitespaceNoisePatternDoesNotSuppressImportant` |
| 3 | Classifier | 非法正则的重要关键词在 ICU 下静默返回 nil → 升级失效 | 无效正则退回字面量匹配 | `testInvalidImportantKeywordRegexFallsBackToLiteralMatch` |
| 4 | LogWatcher | 换文件/跨天前未 flush → 丢上个文件最后一条记录 | 换文件前先 `parser.flush()` | `testRolloverFlushesLastPendingRecordOfPreviousFile` |
| 5 | LogWatcher | 空闲一轮即 flush → 多行续行下一轮到达被丢弃 | 连续 2 轮空闲才 flush(宽限窗口) | `testContinuationArrivingOnePollLaterStillMerges` |
| 6 | Deduper | `lastSeen` 永不清理 → 长跑内存无界增长 | 每次 `shouldAlert` 清理过期签名(语义等价) | `testExpiredSignaturesArePruned` |
| 7 | LogFileLocator | `\d` 匹配 Unicode 数字 → 全角/阿拉伯文件名污染 `.max()` | 正则收窄为 `[0-9]` | `testIgnoresNonAsciiDigitFilenames` |
| 8 | SettingsStore | NaN/Infinity 的 Double 让 JSONEncoder 抛错、`try?` 吞掉 → 整次保存丢失 | `save` 前 `sanitized()` 把非有限值回退默认 | `testNonFiniteDoublesAreSanitizedOnSave` |

**留后处理(#9–11,LOW,当前环境基本触发不到):**

- **#9 Deduper**:NTP 时钟回拨时,抑制分支不刷新 `lastSeen`,可能过度抑制约 2× 冷却时长。
- **#10 Settings**:`Equatable` 在 Double 为 NaN 时 `self != self`(#8 清洗后实际不会持久化 NaN,已大幅缓解)。
- **#11 LogWatcher**:`FileHandle` 打开失败时 `offset = size` 仍推进,可能跳过一段未读字节(EMFILE / stat 后被就地轮转等罕见竞态)。

> 说明:加固使若干行为偏离了 Task 3–9 的原始逐字代码——最显著的是 LogWatcher 的 flush 时机由"空闲 1 轮"改为"空闲 2 轮",既有 3 个 LogWatcher 测试的轮询次数已相应更新。Classifier 的 `noisePatterns` 中"有效但过宽"的正则(如 `.`)仍是用户自负其责,不做拦截。

---

## UI 层实现说明(2026-07-03,Task 10–16 实现后)

UI 层在 **Swift 6 语言模式(swift-tools 6.0,严格并发)** 下实现,较计划原始代码有几处必要偏差,功能等价、更符合并发安全:

- **定时器接线**:不用 `AppDelegate` + `Timer`(计划 Task 15 Step 4 的两方案之一),改由可执行目标内的 `Monitor`(`@MainActor`)持有 `LogWatcher`,用一个 `Task` 轮询循环每秒 `poll()`;`onRecord` 回调用 `MainActor.assumeIsolated` 同步回主线程喂给 `AppModel.handle`(`LogRecord` 为 `Sendable`)。`SentinelApp.init` 创建并 `start()` 该 Monitor。
- **AppModel 依赖**:`import Combine`(而非 `SwiftUI`)提供 `ObservableObject`/`@Published`,避免 `SwiftUI.Settings` 与 `SentinelCore.Settings` 同名冲突。
- **名称消歧**:`SentinelApp` 的设置场景写作 `SwiftUI.Settings { … }`;`SettingsView` 的 keypath 辅助用 `WritableKeyPath<SentinelCore.Settings, …>`。
- **移除脚手架**:删除 Task 0 的 `Placeholder.swift` 与 `SmokeTests`——其 `enum SentinelCore` 遮蔽了模块名 `SentinelCore`,导致 `SentinelCore.Settings` 无法限定;删除后模块名不再被遮蔽。`main_placeholder.swift` 由 `SentinelApp`(`@main`)接管后删除。
- **验收口径**:Task 10–16 以 `swift build` 通过 + `AppModel` 单测(5 个)+ 全量 49 测试为准;toast/声音/菜单栏的**手动冒烟验证归入 Task 17**(打包为 `.app` 后,用 `logDirOverride` 指向临时目录、`feed-log.sh` 灌测试日志),不在本批次。

**当前状态**:SentinelCore + AppLogic 逻辑层完成并加固,UI 层完成并可编译。仅剩 **Task 17(打包 `.app` + 端到端手动验证)**。

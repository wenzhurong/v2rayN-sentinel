# V2rayN Sentinel v2(内核日志监控)Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 v1(只盯 GUI 日志)之上扩展监控 xray/sing-box 内核错误日志(`sbox_*`、`Verror_*`),并对高频连接错误按「目标+类型」聚合成 ×N、突发时升级为重要报警。

**Architecture:** 抽出可插拔 `HeaderMatcher`(Serilog/sing-box/xray 三种格式),把 `LogFileLocator`/`LogWatcher` 泛化为按"文件名模式 + matcher"工作(v1 默认值不变、旧测试全绿);新增 `MultiWatcher` 管多个 `LogSource`;`AppModel` 按 source 路由,内核源经 `Aggregator`(聚合/突发升级/冷却)再报警;`ToastManager` 支持键控 toast 更新。

**Tech Stack:** Swift 6 / SwiftPM,AppKit + SwiftUI,XCTest。零第三方依赖。

## Global Constraints

- **平台**:macOS 14.0+,arch arm64。
- **零第三方依赖**;仅系统框架。
- **对 v2rayN 零侵入**:只读 `~/Library/Application Support/v2rayN/guiLogs/`,不写不锁不联网。
- **纯增量扩展**:不回改 v1 已加固的逻辑;v1 全部 49 个测试必须保持通过。
- **提交规则**:作者仅 repo owner,**不加 `Co-Authored-By` trailer**(见仓库 CLAUDE.md)。
- **网络护栏**:本地/单线程/TDD;不起后台任务;push 需显式批准(见仓库 CLAUDE.md)。
- **监控文件名(逐字来自 spec)**:gui `^[0-9]{4}-[0-9]{2}-[0-9]{2}\.txt$`、singbox `^sbox_[0-9]{4}-[0-9]{2}-[0-9]{2}\.txt$`、xrayError `^Verror_[0-9]{4}-[0-9]{2}-[0-9]{2}\.txt$`;**不监控** `Vaccess_*`。
- **默认参数(逐字来自 spec)**:突发窗口 30s、阈值 20 次、升级冷却 300s、内核报警门槛 Error(默认不含 Warning)、聚合 toast 空闲 10s。

---

### Task 1: HeaderMatcher 协议 + LogParser 可插拔化(保持 v1 行为)

**Files:**
- Create: `Sources/SentinelCore/HeaderMatcher.swift`
- Modify: `Sources/SentinelCore/LogParser.swift`
- Test: `Tests/SentinelCoreTests/HeaderMatcherTests.swift`

**Interfaces:**
- Produces:
  - `public protocol HeaderMatcher: Sendable { func match(_ line: String) -> (String, LogLevel, String)? }`
  - `public struct SerilogHeaderMatcher: HeaderMatcher { public init() }`(即 v1 的行头正则)
  - `LogParser` 新增 `public init(matcher: any HeaderMatcher = SerilogHeaderMatcher())`;`consume`/`flush` 改用注入的 matcher;保留 `static func parseHeader(_:) -> (String, LogLevel, String)?`(委托 Serilog matcher,向后兼容)。

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import SentinelCore

final class HeaderMatcherTests: XCTestCase {
    func testSerilogMatcherParsesGuiLine() {
        let m = SerilogHeaderMatcher()
        let r = m.match("2026-07-13 06:59:56.1234-ERROR boom")
        XCTAssertEqual(r?.0, "2026-07-13 06:59:56.1234")
        XCTAssertEqual(r?.1, .error)
        XCTAssertEqual(r?.2, "boom")
    }
    func testSerilogMatcherRejectsNonHeader() {
        XCTAssertNil(SerilogHeaderMatcher().match("    continuation"))
    }
    func testLogParserUsesInjectedMatcherByDefaultSerilog() {
        let p = LogParser()   // 默认 Serilog
        _ = p.consume("2026-07-13 09:00:00.0000-INFO started")
        let rec = p.consume("2026-07-13 09:00:01.0000-ERROR boom")
        XCTAssertEqual(rec?.level, .info)
        XCTAssertEqual(rec?.message, "started")
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --filter HeaderMatcherTests`
Expected: 编译失败("cannot find 'SerilogHeaderMatcher'")。

- [ ] **Step 3: 实现 HeaderMatcher.swift**

```swift
import Foundation

public protocol HeaderMatcher: Sendable {
    /// 若该行是记录行头,返回 (时间戳, 级别, 正文);否则 nil(续行)。
    func match(_ line: String) -> (String, LogLevel, String)?
}

public struct SerilogHeaderMatcher: HeaderMatcher {
    public init() {}

    private static let regex = try! NSRegularExpression(
        pattern: #"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+)-([A-Za-z]+) ?(.*)$"#
    )

    public func match(_ line: String) -> (String, LogLevel, String)? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let m = SerilogHeaderMatcher.regex.firstMatch(in: line, options: [], range: range) else {
            return nil
        }
        func g(_ i: Int) -> String {
            guard let r = Range(m.range(at: i), in: line) else { return "" }
            return String(line[r])
        }
        let level = LogLevel(rawValue: g(2).uppercased()) ?? .unknown
        return (g(1), level, g(3))
    }
}
```

- [ ] **Step 4: 改 LogParser 用注入 matcher(保留静态 parseHeader)**

将 `Sources/SentinelCore/LogParser.swift` 全文替换为:
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

    private let matcher: any HeaderMatcher
    private var pending: Pending?

    public init(matcher: any HeaderMatcher = SerilogHeaderMatcher()) {
        self.matcher = matcher
    }

    /// 向后兼容:v1 用的静态解析,固定 Serilog 格式。
    public static func parseHeader(_ line: String) -> (String, LogLevel, String)? {
        SerilogHeaderMatcher().match(line)
    }

    public func consume(_ line: String) -> LogRecord? {
        if let (ts, level, msg) = matcher.match(line) {
            let completed = flush()
            pending = Pending(timestamp: ts, level: level,
                              firstMessage: msg, firstRaw: line, extra: [])
            return completed
        } else {
            pending?.extra.append(line)
            return nil
        }
    }

    public func flush() -> LogRecord? {
        guard let p = pending else { return nil }
        pending = nil
        let message = ([p.firstMessage] + p.extra).joined(separator: "\n")
        let raw = ([p.firstRaw] + p.extra).joined(separator: "\n")
        return LogRecord(timestamp: p.timestamp, level: p.level, message: message, raw: raw)
    }
}
```

- [ ] **Step 5: 运行,确认通过 + v1 回归**

Run: `swift test --filter HeaderMatcherTests && swift test --filter LogParserTests`
Expected: HeaderMatcherTests 3 个 PASS;v1 LogParserTests 5 个仍 PASS。

- [ ] **Step 6: 提交**

```bash
git add Sources/SentinelCore/HeaderMatcher.swift Sources/SentinelCore/LogParser.swift Tests/SentinelCoreTests/HeaderMatcherTests.swift
git commit -m "refactor: make LogParser header matching pluggable (Serilog default)"
```

---

### Task 2: sing-box 格式解析器 SingboxHeaderMatcher

**Files:**
- Create: `Sources/SentinelCore/SingboxHeaderMatcher.swift`
- Test: `Tests/SentinelCoreTests/SingboxHeaderMatcherTests.swift`

**Interfaces:**
- Consumes: `HeaderMatcher`、`LogLevel`。
- Produces: `public struct SingboxHeaderMatcher: HeaderMatcher { public init() }`。识别 `<tz> YYYY-MM-DD HH:MM:SS LEVEL 正文`;时区前缀丢弃;正文含 `[连接id 时长]`。级别映射:TRACE/DEBUG→.debug、INFO→.info、WARN→.warn、ERROR→.error、FATAL/PANIC→.fatal。

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import SentinelCore

final class SingboxHeaderMatcherTests: XCTestCase {
    private let m = SingboxHeaderMatcher()

    func testParsesConnectionError() {
        let line = "+0530 2026-07-06 19:31:37 ERROR [1456328237 5.0s] connection: open connection to 172.18.0.1:7881 using outbound/direct[direct]: dial tcp 172.18.0.1:7881: i/o timeout"
        let r = m.match(line)
        XCTAssertEqual(r?.0, "2026-07-06 19:31:37")
        XCTAssertEqual(r?.1, .error)
        XCTAssertEqual(r?.2, "[1456328237 5.0s] connection: open connection to 172.18.0.1:7881 using outbound/direct[direct]: dial tcp 172.18.0.1:7881: i/o timeout")
    }
    func testColonTimezoneAlsoAccepted() {
        let r = m.match("+05:30 2026-07-06 19:31:37 WARN something")
        XCTAssertEqual(r?.1, .warn)
        XCTAssertEqual(r?.2, "something")
    }
    func testPanicMapsToFatal() {
        XCTAssertEqual(m.match("+0000 2026-07-06 19:31:37 PANIC boom")?.1, .fatal)
    }
    func testNonHeaderReturnsNil() {
        XCTAssertNil(m.match("    at stack frame"))
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --filter SingboxHeaderMatcherTests`
Expected: 编译失败("cannot find 'SingboxHeaderMatcher'")。

- [ ] **Step 3: 实现**

```swift
import Foundation

public struct SingboxHeaderMatcher: HeaderMatcher {
    public init() {}

    // <tz> <date> <time> <LEVEL> <message> ;时区 +0530 或 +05:30 皆可。
    private static let regex = try! NSRegularExpression(
        pattern: #"^[+-]\d{2}:?\d{2} (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) ([A-Z]+) (.*)$"#
    )

    public func match(_ line: String) -> (String, LogLevel, String)? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let m = SingboxHeaderMatcher.regex.firstMatch(in: line, options: [], range: range) else {
            return nil
        }
        func g(_ i: Int) -> String {
            guard let r = Range(m.range(at: i), in: line) else { return "" }
            return String(line[r])
        }
        let level: LogLevel
        switch g(2) {
        case "TRACE", "DEBUG": level = .debug
        case "INFO": level = .info
        case "WARN": level = .warn
        case "ERROR": level = .error
        case "FATAL", "PANIC": level = .fatal
        default: level = .unknown
        }
        return (g(1), level, g(3))
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --filter SingboxHeaderMatcherTests`
Expected: 4 个 PASS。

- [ ] **Step 5: 提交**

```bash
git add Sources/SentinelCore/SingboxHeaderMatcher.swift Tests/SentinelCoreTests/SingboxHeaderMatcherTests.swift
git commit -m "feat: add sing-box log header matcher"
```

---

### Task 3: xray 格式解析器 XrayHeaderMatcher

**Files:**
- Create: `Sources/SentinelCore/XrayHeaderMatcher.swift`
- Test: `Tests/SentinelCoreTests/XrayHeaderMatcherTests.swift`

**Interfaces:**
- Produces: `public struct XrayHeaderMatcher: HeaderMatcher { public init() }`。识别 `YYYY/MM/DD HH:MM:SS[.ffffff] [Level] 正文`;级别映射:Debug→.debug、Info→.info、Warning→.warn、Error→.error。

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import SentinelCore

final class XrayHeaderMatcherTests: XCTestCase {
    private let m = XrayHeaderMatcher()

    func testParsesWarning() {
        let r = m.match("2026/07/13 06:59:56.054278 [Warning] core: Xray 26.6.1 started")
        XCTAssertEqual(r?.0, "2026/07/13 06:59:56.054278")
        XCTAssertEqual(r?.1, .warn)
        XCTAssertEqual(r?.2, "core: Xray 26.6.1 started")
    }
    func testParsesErrorWithoutFraction() {
        let r = m.match("2026/07/13 07:00:00 [Error] failed to dial")
        XCTAssertEqual(r?.1, .error)
        XCTAssertEqual(r?.2, "failed to dial")
    }
    func testNonHeaderReturnsNil() {
        XCTAssertNil(m.match("  > some continuation"))
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --filter XrayHeaderMatcherTests`
Expected: 编译失败("cannot find 'XrayHeaderMatcher'")。

- [ ] **Step 3: 实现**

```swift
import Foundation

public struct XrayHeaderMatcher: HeaderMatcher {
    public init() {}

    private static let regex = try! NSRegularExpression(
        pattern: #"^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?) \[([A-Za-z]+)\] (.*)$"#
    )

    public func match(_ line: String) -> (String, LogLevel, String)? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let m = XrayHeaderMatcher.regex.firstMatch(in: line, options: [], range: range) else {
            return nil
        }
        func g(_ i: Int) -> String {
            guard let r = Range(m.range(at: i), in: line) else { return "" }
            return String(line[r])
        }
        let level: LogLevel
        switch g(2) {
        case "Debug": level = .debug
        case "Info": level = .info
        case "Warning": level = .warn
        case "Error": level = .error
        default: level = .unknown
        }
        return (g(1), level, g(3))
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --filter XrayHeaderMatcherTests`
Expected: 3 个 PASS。

- [ ] **Step 5: 提交**

```bash
git add Sources/SentinelCore/XrayHeaderMatcher.swift Tests/SentinelCoreTests/XrayHeaderMatcherTests.swift
git commit -m "feat: add xray log header matcher"
```

---

### Task 4: 泛化 LogFileLocator 与 LogWatcher(按模式 + matcher;保持 v1 行为)

**Files:**
- Modify: `Sources/SentinelCore/LogFileLocator.swift`
- Modify: `Sources/SentinelCore/LogWatcher.swift`
- Test: `Tests/SentinelCoreTests/LogFileLocatorTests.swift`(追加)
- Test: `Tests/SentinelCoreTests/LogWatcherTests.swift`(追加)

**Interfaces:**
- Produces:
  - `LogFileLocator.newestMatchingFile(in filenames: [String], pattern: String) -> String?`(pattern 为不带锚点的正则体;内部加 `^…$`);`newestDateFile` 保留,委托前者。
  - `LogWatcher` 新增 init 参数 `filePattern: String = #"[0-9]{4}-[0-9]{2}-[0-9]{2}\.txt"#` 与 `headerMatcher: any HeaderMatcher = SerilogHeaderMatcher()`;内部改用 `newestMatchingFile(in:pattern:)` 与 `LogParser(matcher:)`。默认值 = v1 行为。

- [ ] **Step 1: 写失败测试(定位器 + 监控器各一)**

`LogFileLocatorTests.swift` 追加:
```swift
    func testNewestMatchingFilePicksPrefixed() {
        let names = ["sbox_2026-07-12.txt", "sbox_2026-07-13.txt", "2026-07-13.txt", "Vaccess_2026-07-13.txt"]
        XCTAssertEqual(
            LogFileLocator.newestMatchingFile(in: names, pattern: #"sbox_[0-9]{4}-[0-9]{2}-[0-9]{2}\.txt"#),
            "sbox_2026-07-13.txt")
    }
```

`LogWatcherTests.swift` 追加:
```swift
    func testWatchesSboxFileWithSingboxMatcher() throws {
        try write("sbox_2026-07-13.txt",
            "+0530 2026-07-13 09:00:00 ERROR [1 5.0s] dial tcp 1.2.3.4:80: i/o timeout\n")
        var got: [LogRecord] = []
        let w = LogWatcher(directory: dir, startAtEnd: false,
                           filePattern: #"sbox_[0-9]{4}-[0-9]{2}-[0-9]{2}\.txt"#,
                           headerMatcher: SingboxHeaderMatcher())
        w.onRecord = { got.append($0) }
        w.poll(); w.poll(); w.poll()   // 读到 -> 空闲2轮 flush
        XCTAssertEqual(got.map(\.level), [.error])
        XCTAssertEqual(got.first?.message, "[1 5.0s] dial tcp 1.2.3.4:80: i/o timeout")
    }
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --filter LogFileLocatorTests/testNewestMatchingFilePicksPrefixed --filter LogWatcherTests/testWatchesSboxFileWithSingboxMatcher`
Expected: 编译失败(`newestMatchingFile` / 新 init 参数不存在)。

- [ ] **Step 3: 改 LogFileLocator.swift(全文替换)**

```swift
import Foundation

public enum LogFileLocator {
    /// 从目录文件名中选出匹配 `pattern`(不含锚点)且最大的文件名。
    public static func newestMatchingFile(in filenames: [String], pattern: String) -> String? {
        let anchored = "^" + pattern + "$"
        let matched = filenames.filter {
            $0.range(of: anchored, options: .regularExpression) != nil
        }
        return matched.max()
    }

    /// v1 兼容:当天 GUI 日志 `YYYY-MM-DD.txt`。
    public static func newestDateFile(in filenames: [String]) -> String? {
        newestMatchingFile(in: filenames, pattern: #"[0-9]{4}-[0-9]{2}-[0-9]{2}\.txt"#)
    }
}
```

- [ ] **Step 4: 改 LogWatcher.swift(加两个带默认值的 init 参数并改用泛化 API)**

将 `LogWatcher` 的存储属性、init、以及 poll 中定位/解析处改为:
```swift
    private let filePattern: String
    private let headerMatcher: any HeaderMatcher
    // ...(其余 currentFile/offset/parser/buffer/idlePolls 不变)

    public init(directory: URL, startAtEnd: Bool = true,
                fileManager: FileManager = .default,
                filePattern: String = #"[0-9]{4}-[0-9]{2}-[0-9]{2}\.txt"#,
                headerMatcher: any HeaderMatcher = SerilogHeaderMatcher()) {
        self.directory = directory
        self.startAtEnd = startAtEnd
        self.fileManager = fileManager
        self.filePattern = filePattern
        self.headerMatcher = headerMatcher
        self.parser = LogParser(matcher: headerMatcher)
    }
```
并在 `poll()` 中:
- 定位改为 `guard let newest = LogFileLocator.newestMatchingFile(in: names, pattern: filePattern) else { return }`
- 换文件重置解析器处 `parser = LogParser()` 改为 `parser = LogParser(matcher: headerMatcher)`

> 注:`parser` 属性声明从 `= LogParser()` 改为在 init 中赋值;把 `private var parser = LogParser()` 改成 `private var parser: LogParser`。

- [ ] **Step 5: 运行,确认通过 + v1 回归**

Run: `swift test --filter LogFileLocatorTests --filter LogWatcherTests`
Expected: 全部 PASS(含 v1 既有用例)。

- [ ] **Step 6: 提交**

```bash
git add Sources/SentinelCore/LogFileLocator.swift Sources/SentinelCore/LogWatcher.swift Tests/SentinelCoreTests/LogFileLocatorTests.swift Tests/SentinelCoreTests/LogWatcherTests.swift
git commit -m "feat: generalize LogFileLocator/LogWatcher by filename pattern + matcher"
```

---

### Task 5: 连接错误信息提取 ConnectionErrorParser

**Files:**
- Create: `Sources/SentinelCore/ConnectionError.swift`
- Test: `Tests/SentinelCoreTests/ConnectionErrorTests.swift`

**Interfaces:**
- Produces:
  - `public struct ConnectionErrorInfo: Equatable, Sendable { public let target: String?; public let kind: String }`
  - `public enum ConnectionErrorParser { public static func extract(from message: String) -> ConnectionErrorInfo }`
- 从 `dial tcp <host:port>: <reason>` 抠 target/kind;抠不出 → target=nil、kind = 去空白后的整条正文。

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import SentinelCore

final class ConnectionErrorTests: XCTestCase {
    func testExtractsDialTimeout() {
        let msg = "[1 5.0s] connection: open connection to 172.18.0.1:7881 using outbound/direct[direct]: dial tcp 172.18.0.1:7881: i/o timeout"
        let info = ConnectionErrorParser.extract(from: msg)
        XCTAssertEqual(info.target, "172.18.0.1:7881")
        XCTAssertEqual(info.kind, "i/o timeout")
    }
    func testExtractsRefused() {
        let info = ConnectionErrorParser.extract(from: "... dial tcp 10.0.0.1:443: connection refused")
        XCTAssertEqual(info.target, "10.0.0.1:443")
        XCTAssertEqual(info.kind, "connection refused")
    }
    func testFallbackWhenNoDial() {
        let info = ConnectionErrorParser.extract(from: "some other error")
        XCTAssertNil(info.target)
        XCTAssertEqual(info.kind, "some other error")
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --filter ConnectionErrorTests`
Expected: 编译失败("cannot find 'ConnectionErrorParser'")。

- [ ] **Step 3: 实现**

```swift
import Foundation

public struct ConnectionErrorInfo: Equatable, Sendable {
    public let target: String?
    public let kind: String
    public init(target: String?, kind: String) {
        self.target = target
        self.kind = kind
    }
}

public enum ConnectionErrorParser {
    // dial tcp|udp <host:port>: <reason>   (host:port 中间冒号无空格,reason 前是"冒号+空格")
    private static let dialRegex = try! NSRegularExpression(
        pattern: #"dial (?:tcp|udp) (.+?): (.+)$"#
    )

    public static func extract(from message: String) -> ConnectionErrorInfo {
        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        if let m = dialRegex.firstMatch(in: message, options: [], range: range) {
            func g(_ i: Int) -> String {
                guard let r = Range(m.range(at: i), in: message) else { return "" }
                return String(message[r])
            }
            return ConnectionErrorInfo(target: g(1), kind: g(2).trimmingCharacters(in: .whitespaces))
        }
        return ConnectionErrorInfo(target: nil,
                                   kind: message.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --filter ConnectionErrorTests`
Expected: 3 个 PASS。

- [ ] **Step 5: 提交**

```bash
git add Sources/SentinelCore/ConnectionError.swift Tests/SentinelCoreTests/ConnectionErrorTests.swift
git commit -m "feat: extract target/kind from connection error messages"
```

---

### Task 6: 聚合器 Aggregator(含聚合 key、计数、突发升级、冷却、空闲重置、剪枝)

**Files:**
- Create: `Sources/SentinelCore/Aggregator.swift`
- Test: `Tests/SentinelCoreTests/AggregatorTests.swift`

**Interfaces:**
- Consumes: `LogRecord`、`ConnectionErrorParser`。
- Produces:
  - `Aggregator.key(for record: LogRecord) -> String`(static;target|kind,抠不出则去掉 `[连接id 时长]` 前缀后的正文)。
  - `public struct AggregatorParams: Sendable { burstWindow, burstThreshold, escalationCooldown, idleReset }`
  - `public struct AggregateOutcome: Equatable, Sendable { public let key: String; public let count: Int; public let escalate: Bool }`
  - `public final class Aggregator { init(params:); func ingest(key: String, now: Date) -> AggregateOutcome; var trackedCount: Int }`
- 语义:每次 ingest → count+1、lastSeen=now;若距上次 > idleReset 则先把 count/窗口清零(视为新一波);窗口 `now-windowStart>burstWindow` 则重置窗口;windowCount+1;当 windowCount≥threshold 且不在冷却中 → escalate=true 并置冷却;每次 ingest 先剪除 lastSeen 超过 `max(escalationCooldown, idleReset)` 的过期 key。

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import SentinelCore

final class AggregatorTests: XCTestCase {
    private func rec(_ msg: String) -> LogRecord {
        LogRecord(timestamp: "t", level: .error, message: msg, raw: msg)
    }
    private func agg() -> Aggregator {
        Aggregator(params: AggregatorParams(burstWindow: 30, burstThreshold: 3,
                                            escalationCooldown: 300, idleReset: 10))
    }
    private func t(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

    func testKeyGroupsByTargetAndKind() {
        let a = Aggregator.key(for: rec("[1 5.0s] dial tcp 1.2.3.4:80: i/o timeout"))
        let b = Aggregator.key(for: rec("[999 5.0s] dial tcp 1.2.3.4:80: i/o timeout"))
        XCTAssertEqual(a, b)   // 连接id 不同但目标+类型相同 -> 同 key
    }
    func testCountAccumulatesAndEscalatesAtThreshold() {
        let a = agg()
        XCTAssertFalse(a.ingest(key: "k", now: t(0)).escalate)   // 1
        XCTAssertFalse(a.ingest(key: "k", now: t(1)).escalate)   // 2
        let third = a.ingest(key: "k", now: t(2))               // 3 -> 阈值
        XCTAssertTrue(third.escalate)
        XCTAssertEqual(third.count, 3)
    }
    func testCooldownPreventsReEscalation() {
        let a = agg()
        _ = a.ingest(key: "k", now: t(0)); _ = a.ingest(key: "k", now: t(1))
        XCTAssertTrue(a.ingest(key: "k", now: t(2)).escalate)    // 升级
        XCTAssertFalse(a.ingest(key: "k", now: t(3)).escalate)   // 冷却中
    }
    func testIdleResetsCount() {
        let a = agg()
        _ = a.ingest(key: "k", now: t(0))
        let after = a.ingest(key: "k", now: t(100))              // 距上次 100s > idleReset(10)
        XCTAssertEqual(after.count, 1)                          // 计数重置
    }
    func testExpiredKeysPruned() {
        let a = agg()
        _ = a.ingest(key: "a", now: t(0))
        _ = a.ingest(key: "b", now: t(1000))                    // a 早已过期
        XCTAssertEqual(a.trackedCount, 1)
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --filter AggregatorTests`
Expected: 编译失败("cannot find 'Aggregator'")。

- [ ] **Step 3: 实现**

```swift
import Foundation

public struct AggregatorParams: Sendable {
    public var burstWindow: TimeInterval
    public var burstThreshold: Int
    public var escalationCooldown: TimeInterval
    public var idleReset: TimeInterval
    public init(burstWindow: TimeInterval, burstThreshold: Int,
                escalationCooldown: TimeInterval, idleReset: TimeInterval) {
        self.burstWindow = burstWindow
        self.burstThreshold = burstThreshold
        self.escalationCooldown = escalationCooldown
        self.idleReset = idleReset
    }
}

public struct AggregateOutcome: Equatable, Sendable {
    public let key: String
    public let count: Int
    public let escalate: Bool
}

public final class Aggregator {
    private struct State {
        var count: Int
        var windowStart: Date
        var windowCount: Int
        var lastSeen: Date
        var escalatedUntil: Date?
    }

    private var states: [String: State] = [:]
    private let params: AggregatorParams

    public init(params: AggregatorParams) { self.params = params }

    public var trackedCount: Int { states.count }

    /// 聚合 key:优先 target|kind;抠不出则去掉 `[连接id 时长]` 前缀后的正文。
    public static func key(for record: LogRecord) -> String {
        let info = ConnectionErrorParser.extract(from: record.message)
        if let t = info.target { return "\(t)|\(info.kind)" }
        let stripped = record.message.replacingOccurrences(
            of: #"^\[\d+ [\d.]+s?\] "#, with: "", options: .regularExpression)
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func ingest(key: String, now: Date) -> AggregateOutcome {
        prune(now: now)
        var s = states[key] ?? State(count: 0, windowStart: now, windowCount: 0,
                                     lastSeen: now, escalatedUntil: nil)
        // 空闲过久 -> 视为新一波,清零计数与窗口(保留冷却时间)
        if now.timeIntervalSince(s.lastSeen) > params.idleReset {
            s.count = 0
            s.windowStart = now
            s.windowCount = 0
        }
        s.count += 1
        s.lastSeen = now
        if now.timeIntervalSince(s.windowStart) > params.burstWindow {
            s.windowStart = now
            s.windowCount = 0
        }
        s.windowCount += 1
        var escalate = false
        if s.windowCount >= params.burstThreshold {
            if let until = s.escalatedUntil {
                if now >= until { escalate = true }
            } else {
                escalate = true
            }
            if escalate { s.escalatedUntil = now.addingTimeInterval(params.escalationCooldown) }
        }
        states[key] = s
        return AggregateOutcome(key: key, count: s.count, escalate: escalate)
    }

    private func prune(now: Date) {
        guard !states.isEmpty else { return }
        let retain = max(params.escalationCooldown, params.idleReset)
        states = states.filter { now.timeIntervalSince($0.value.lastSeen) <= retain }
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --filter AggregatorTests`
Expected: 6 个 PASS。

- [ ] **Step 5: 提交**

```bash
git add Sources/SentinelCore/Aggregator.swift Tests/SentinelCoreTests/AggregatorTests.swift
git commit -m "feat: add Aggregator (per-key count, burst escalation, cooldown, idle reset)"
```

---

### Task 7: 多源监控 MultiWatcher + LogSource

**Files:**
- Create: `Sources/SentinelCore/LogSource.swift`
- Create: `Sources/SentinelCore/MultiWatcher.swift`
- Test: `Tests/SentinelCoreTests/MultiWatcherTests.swift`

**Interfaces:**
- Consumes: `LogWatcher`、`HeaderMatcher`、各 matcher。
- Produces:
  - `public enum SourceKind: Sendable { case gui, singbox, xrayError }`
  - `public struct LogSource: Sendable { public let kind: SourceKind; public let filePattern: String; public let matcher: any HeaderMatcher; public let aggregates: Bool }`,以及 `static let gui/singbox/xrayError`。
  - `public final class MultiWatcher { init(directory:, sources: [LogSource], startAtEnd:, fileManager:); var onRecord: ((LogRecord, SourceKind) -> Void)?; func poll() }`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import SentinelCore

final class MultiWatcherTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("mw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }
    private func write(_ n: String, _ t: String) throws {
        try t.data(using: .utf8)!.write(to: dir.appendingPathComponent(n))
    }

    func testRoutesRecordsToTheirSource() throws {
        try write("2026-07-13.txt", "2026-07-13 09:00:00.0000-ERROR gui boom\n")
        try write("sbox_2026-07-13.txt", "+0530 2026-07-13 09:00:00 ERROR [1 5.0s] dial tcp 1.2.3.4:80: i/o timeout\n")
        var got: [(SourceKind, String)] = []
        let mw = MultiWatcher(directory: dir, sources: [.gui, .singbox], startAtEnd: false)
        mw.onRecord = { rec, kind in got.append((kind, rec.message)) }
        mw.poll(); mw.poll(); mw.poll()
        XCTAssertTrue(got.contains { $0.0 == .gui && $0.1 == "gui boom" })
        XCTAssertTrue(got.contains { $0.0 == .singbox && $0.1.contains("i/o timeout") })
    }
    func testMissingSourceFileIsSilent() throws {
        // 只有 gui 文件,singbox 源没有对应文件 -> 不报错、不产出 singbox 记录
        try write("2026-07-13.txt", "2026-07-13 09:00:00.0000-INFO hi\n")
        var kinds: [SourceKind] = []
        let mw = MultiWatcher(directory: dir, sources: [.gui, .singbox], startAtEnd: false)
        mw.onRecord = { _, k in kinds.append(k) }
        mw.poll(); mw.poll()
        XCTAssertFalse(kinds.contains(.singbox))
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --filter MultiWatcherTests`
Expected: 编译失败("cannot find 'MultiWatcher'/'LogSource'")。

- [ ] **Step 3: 实现 LogSource.swift**

```swift
import Foundation

public enum SourceKind: Sendable { case gui, singbox, xrayError }

public struct LogSource: Sendable {
    public let kind: SourceKind
    public let filePattern: String
    public let matcher: any HeaderMatcher
    public let aggregates: Bool

    public init(kind: SourceKind, filePattern: String, matcher: any HeaderMatcher, aggregates: Bool) {
        self.kind = kind
        self.filePattern = filePattern
        self.matcher = matcher
        self.aggregates = aggregates
    }

    public static let gui = LogSource(
        kind: .gui, filePattern: #"[0-9]{4}-[0-9]{2}-[0-9]{2}\.txt"#,
        matcher: SerilogHeaderMatcher(), aggregates: false)
    public static let singbox = LogSource(
        kind: .singbox, filePattern: #"sbox_[0-9]{4}-[0-9]{2}-[0-9]{2}\.txt"#,
        matcher: SingboxHeaderMatcher(), aggregates: true)
    public static let xrayError = LogSource(
        kind: .xrayError, filePattern: #"Verror_[0-9]{4}-[0-9]{2}-[0-9]{2}\.txt"#,
        matcher: XrayHeaderMatcher(), aggregates: true)
}
```

- [ ] **Step 4: 实现 MultiWatcher.swift**

```swift
import Foundation

public final class MultiWatcher {
    public var onRecord: ((LogRecord, SourceKind) -> Void)?
    private var watchers: [LogWatcher] = []

    public init(directory: URL, sources: [LogSource],
                startAtEnd: Bool = true, fileManager: FileManager = .default) {
        for s in sources {
            let w = LogWatcher(directory: directory, startAtEnd: startAtEnd,
                               fileManager: fileManager,
                               filePattern: s.filePattern, headerMatcher: s.matcher)
            let kind = s.kind
            w.onRecord = { [weak self] rec in self?.onRecord?(rec, kind) }
            watchers.append(w)
        }
    }

    public func poll() {
        for w in watchers { w.poll() }
    }
}
```

- [ ] **Step 5: 运行,确认通过 + 全量回归**

Run: `swift test`
Expected: MultiWatcherTests 2 个 PASS;至此 SentinelCore 全部通过。

- [ ] **Step 6: 提交**

```bash
git add Sources/SentinelCore/LogSource.swift Sources/SentinelCore/MultiWatcher.swift Tests/SentinelCoreTests/MultiWatcherTests.swift
git commit -m "feat: add MultiWatcher over multiple LogSources"
```

---

### Task 8: 设置新增内核监控字段

**Files:**
- Modify: `Sources/SentinelCore/Settings.swift`
- Modify: `Sources/SentinelCore/SettingsStore.swift`
- Test: `Tests/SentinelCoreTests/SettingsTests.swift`(追加)

**Interfaces:**
- Produces: `Settings` 新增字段 `coreMonitoringEnabled: Bool`、`burstWindowSeconds: Double`、`burstThreshold: Int`、`escalationCooldownSeconds: Double`、`coreAlertIncludesWarning: Bool`、`aggregatedToastIdleSeconds: Double`;`Settings.default` 填默认值;`SettingsStore.sanitized` 清洗两个新 Double。

- [ ] **Step 1: 写失败测试**

`SettingsTests.swift` 追加:
```swift
    func testV2DefaultsMatchSpec() {
        let s = Settings.default
        XCTAssertTrue(s.coreMonitoringEnabled)
        XCTAssertEqual(s.burstWindowSeconds, 30)
        XCTAssertEqual(s.burstThreshold, 20)
        XCTAssertEqual(s.escalationCooldownSeconds, 300)
        XCTAssertFalse(s.coreAlertIncludesWarning)
        XCTAssertEqual(s.aggregatedToastIdleSeconds, 10)
    }
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
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --filter SettingsTests/testV2DefaultsMatchSpec`
Expected: 编译失败(字段不存在)。

- [ ] **Step 3: 加字段到 Settings.swift**

在 `Settings` 结构体中,`logDirOverride` 之后加入新存储属性,并加进 `init` 参数与赋值、`static let default`:
```swift
    public var coreMonitoringEnabled: Bool
    public var burstWindowSeconds: Double
    public var burstThreshold: Int
    public var escalationCooldownSeconds: Double
    public var coreAlertIncludesWarning: Bool
    public var aggregatedToastIdleSeconds: Double
```
`init` 末尾追加对应参数(全部带默认值以免打断调用):
```swift
                coreMonitoringEnabled: Bool = true,
                burstWindowSeconds: Double = 30,
                burstThreshold: Int = 20,
                escalationCooldownSeconds: Double = 300,
                coreAlertIncludesWarning: Bool = false,
                aggregatedToastIdleSeconds: Double = 10
```
并在 init 体内 `self.xxx = xxx`;`Settings.default` 用默认值构造(现有调用可不显式传这些,靠默认值)。

- [ ] **Step 4: 扩展 SettingsStore.sanitized**

在 `SettingsStore.sanitized(_:)` 中追加:
```swift
        if !out.burstWindowSeconds.isFinite {
            out.burstWindowSeconds = Settings.default.burstWindowSeconds
        }
        if !out.escalationCooldownSeconds.isFinite {
            out.escalationCooldownSeconds = Settings.default.escalationCooldownSeconds
        }
        if !out.aggregatedToastIdleSeconds.isFinite {
            out.aggregatedToastIdleSeconds = Settings.default.aggregatedToastIdleSeconds
        }
```

- [ ] **Step 5: 运行,确认通过**

Run: `swift test --filter SettingsTests`
Expected: 全部 PASS(含 v1 用例)。

- [ ] **Step 6: 提交**

```bash
git add Sources/SentinelCore/Settings.swift Sources/SentinelCore/SettingsStore.swift Tests/SentinelCoreTests/SettingsTests.swift
git commit -m "feat: add v2 core-monitoring settings fields"
```

---

### Task 9: 协调器路由 + Alerting 扩展(内核源经 Aggregator)

**Files:**
- Modify: `Sources/AppLogic/Alerting.swift`
- Modify: `Sources/AppLogic/AppModel.swift`
- Test: `Tests/AppLogicTests/AppModelTests.swift`(追加 + 更新 SpyAlerter)

**Interfaces:**
- Consumes: `SourceKind`、`Aggregator`、`ConnectionErrorParser`、`Settings`。
- Produces:
  - `Alerting` 新增 `func presentAggregated(key: String, title: String, count: Int, autoDismiss: TimeInterval?)`。
  - `AppModel.handle(_ record: LogRecord, source: SourceKind = .gui, now: Date)`(默认 `.gui` 保持 v1 调用);内核源:级别达门槛 → `Aggregator.ingest` → `presentAggregated`;`escalate` 时 `present(important:true)` + 声音;暂停或 `coreMonitoringEnabled=false` 时不处理内核源。

- [ ] **Step 1: 更新 SpyAlerter 并写失败测试**

`AppModelTests.swift` 中,给 `SpyAlerter` 增加实现并加测试:
```swift
        var aggregated: [(String, Int)] = []
        func presentAggregated(key: String, title: String, count: Int, autoDismiss: TimeInterval?) {
            aggregated.append((key, count))
        }
```
新增测试:
```swift
    private func coreRec(_ msg: String) -> LogRecord {
        LogRecord(timestamp: "t", level: .error, message: msg, raw: msg)
    }

    func testCoreErrorGoesToAggregatedNotToast() {
        let spy = SpyAlerter(); let m = makeModel(spy)
        m.handle(coreRec("[1 5.0s] dial tcp 1.2.3.4:80: i/o timeout"), source: .singbox, now: Date())
        XCTAssertEqual(spy.aggregated.count, 1)
        XCTAssertEqual(spy.aggregated.first?.1, 1)      // count = 1
        XCTAssertTrue(spy.presented.isEmpty)            // 未升级 -> 无重要弹窗
    }
    func testCoreBurstEscalatesToImportantWithSound() {
        let spy = SpyAlerter()
        var s = Settings.default; s.burstThreshold = 3; s.burstWindowSeconds = 30
        let m = AppModel(settings: s, alerter: spy)
        let t0 = Date(timeIntervalSince1970: 0)
        for i in 0..<3 { m.handle(coreRec("[X 5.0s] dial tcp 1.2.3.4:80: i/o timeout"),
                                  source: .singbox, now: t0.addingTimeInterval(Double(i))) }
        XCTAssertEqual(spy.presented.filter { $0.1 }.count, 1)  // 恰升级一次(important)
        XCTAssertEqual(spy.sounds, ["Basso"])
    }
    func testCoreMonitoringDisabledIgnoresCore() {
        let spy = SpyAlerter()
        var s = Settings.default; s.coreMonitoringEnabled = false
        let m = AppModel(settings: s, alerter: spy)
        m.handle(coreRec("dial tcp 1.2.3.4:80: i/o timeout"), source: .singbox, now: Date())
        XCTAssertTrue(spy.aggregated.isEmpty)
        XCTAssertTrue(spy.presented.isEmpty)
    }
    func testGuiPathUnchanged() {   // v1 行为回归:gui 源仍走原路径
        let spy = SpyAlerter(); let m = makeModel(spy)
        m.handle(record(.error, "core crashed"), now: Date())   // source 默认 .gui
        XCTAssertEqual(spy.presented.first?.1, true)
        XCTAssertEqual(spy.sounds, ["Basso"])
    }
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --filter AppModelTests/testCoreErrorGoesToAggregatedNotToast`
Expected: 编译失败(`presentAggregated` / `source:` 参数 / 内核路由不存在)。

- [ ] **Step 3: 扩展 Alerting 协议**

`Sources/AppLogic/Alerting.swift` 中协议追加方法:
```swift
    func presentAggregated(key: String, title: String, count: Int, autoDismiss: TimeInterval?)
```

- [ ] **Step 4: 改 AppModel 支持 source 路由**

在 `AppModel` 中:新增 `private let aggregator: Aggregator`(init 用 settings 构造);把 `handle` 签名改为带 `source` 默认 `.gui`;内核分支实现如下(在 `handle` 中):
```swift
    public func handle(_ record: LogRecord, source: SourceKind = .gui, now: Date) {
        guard monitoring else { return }
        if source == .gui {
            handleGui(record, now: now)   // 原 v1 逻辑抽成私有方法,内容不变
        } else {
            handleCore(record, now: now)
        }
    }

    private func handleCore(_ record: LogRecord, now: Date) {
        guard settings.coreMonitoringEnabled else { return }
        let isErr = record.level.isError
            || (settings.coreAlertIncludesWarning && record.level == .warn)
        guard isErr else { return }

        let info = ConnectionErrorParser.extract(from: record.message)
        let key = Aggregator.key(for: record)
        let outcome = aggregator.ingest(key: key, now: now)
        let title = info.target.map { "\($0)  \(info.kind)" } ?? record.message

        let entry = HistoryEntry(
            timestamp: record.timestamp, level: record.level, message: title,
            signature: key, classification: .ordinary, count: outcome.count)
        historyStore.record(entry)
        history = historyStore.entries

        alerter.presentAggregated(key: key, title: title, count: outcome.count,
                                  autoDismiss: settings.aggregatedToastIdleSeconds)
        if outcome.escalate {
            let important = HistoryEntry(
                timestamp: record.timestamp, level: record.level,
                message: "持续故障:\(title)(×\(outcome.count))",
                signature: key, classification: .important, count: outcome.count)
            alerter.present(entry: important, important: true, autoDismiss: nil)
            if settings.soundEnabled { alerter.playSound(named: settings.soundName) }
        }
    }
```
`init` 中构造 aggregator:
```swift
        self.aggregator = Aggregator(params: AggregatorParams(
            burstWindow: settings.burstWindowSeconds,
            burstThreshold: settings.burstThreshold,
            escalationCooldown: settings.escalationCooldownSeconds,
            idleReset: settings.aggregatedToastIdleSeconds))
```
把原 `handle` 主体(分级→去重→present/sound→历史)原样搬进 `private func handleGui(_ record: LogRecord, now: Date)`。

- [ ] **Step 5: 运行,确认通过 + 全量回归**

Run: `swift test`
Expected: 新 4 个测试 + v1 AppModelTests 全 PASS;SentinelCore 全绿。

- [ ] **Step 6: 提交**

```bash
git add Sources/AppLogic/Alerting.swift Sources/AppLogic/AppModel.swift Tests/AppLogicTests/AppModelTests.swift
git commit -m "feat: route core-log records through Aggregator with burst escalation"
```

---

### Task 10: ToastManager 键控 toast + ToastAlerter 聚合展示

**Files:**
- Modify: `Sources/V2rayNSentinel/ToastManager.swift`
- Modify: `Sources/V2rayNSentinel/ToastAlerter.swift`
- Create: `Sources/V2rayNSentinel/AggregatedToastView.swift`

**Interfaces:**
- Consumes: `Alerting`(含新 `presentAggregated`)。
- Produces:
  - `ToastManager.showOrUpdateAggregated(key: String, title: String, count: Int, autoDismiss: TimeInterval?, screen: NSScreen)` — 同 key 有活 toast 就更新其文案与空闲计时;否则新建。
  - `ToastAlerter.presentAggregated(...)` 落到上面的键控 API,选屏同 `present`。

- [ ] **Step 1: 实现 AggregatedToastView.swift**

```swift
import SwiftUI

struct AggregatedToastView: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("连接错误")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(count > 1 ? "\(title)  ×\(count)" : title)
                    .font(.callout).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 360, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
```

- [ ] **Step 2: 给 ToastManager 加键控 API**

在 `ToastManager` 中新增(与现有 `show` 并存):
```swift
    private var keyedWindows: [String: ToastWindow] = [:]

    func showOrUpdateAggregated(key: String, title: String, count: Int,
                                autoDismiss: TimeInterval?, screen: NSScreen) {
        if let existing = keyedWindows[key] {
            existing.contentView = NSHostingView(rootView: AggregatedToastView(title: title, count: count))
            existing.setContentSize(existing.contentView!.fittingSize)
            scheduleKeyedDismiss(key: key, after: autoDismiss)
            return
        }
        let window = ToastWindow(content: AggregatedToastView(title: title, count: count))
        keyedWindows[key] = window
        windows.append(window)
        layout(on: screen)
        window.orderFrontRegardless()
        scheduleKeyedDismiss(key: key, after: autoDismiss)
    }

    private func scheduleKeyedDismiss(key: String, after seconds: TimeInterval?) {
        guard let seconds else { return }
        let token = UUID()
        keyedDismissToken[key] = token
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.keyedDismissToken[key] == token else { return }
            if let w = self.keyedWindows[key] {
                w.close()
                self.windows.removeAll { $0 === w }
                self.keyedWindows[key] = nil
                self.keyedDismissToken[key] = nil
                if let screen = w.screen ?? NSScreen.main { self.layout(on: screen) }
            }
        }
    }
```
并加存储属性 `private var keyedDismissToken: [String: UUID] = [:]`。
> 说明:`import SwiftUI` 需加到 ToastManager 顶部(用到 NSHostingView/AggregatedToastView)。

- [ ] **Step 3: ToastAlerter 实现 presentAggregated**

`ToastAlerter` 追加:
```swift
    func presentAggregated(key: String, title: String, count: Int, autoDismiss: TimeInterval?) {
        toasts.showOrUpdateAggregated(key: key, title: title, count: count,
                                      autoDismiss: autoDismiss, screen: resolveScreen())
    }
```

- [ ] **Step 4: 验证编译**

Run: `swift build`
Expected: 构建成功。

- [ ] **Step 5: 提交**

```bash
git add Sources/V2rayNSentinel/AggregatedToastView.swift Sources/V2rayNSentinel/ToastManager.swift Sources/V2rayNSentinel/ToastAlerter.swift
git commit -m "feat: keyed aggregated toast that updates its count in place"
```

---

### Task 11: Monitor 用 MultiWatcher 驱动全部源

**Files:**
- Modify: `Sources/V2rayNSentinel/Monitor.swift`

**Interfaces:**
- Consumes: `MultiWatcher`、`AppModel.handle(_:source:now:)`。
- Produces: `Monitor` 内部用 `MultiWatcher(directory:, sources: [.gui, .singbox, .xrayError])`,`onRecord` 把 `(record, kind)` 转 `model.handle(record, source: kind, now: Date())`。

- [ ] **Step 1: 改 Monitor.swift(全文替换)**

```swift
import Foundation
import SentinelCore
import AppLogic

@MainActor
final class Monitor {
    private let watcher: MultiWatcher
    private let model: AppModel
    private var task: Task<Void, Never>?

    init(model: AppModel, directory: URL) {
        self.model = model
        self.watcher = MultiWatcher(directory: directory,
                                    sources: [.gui, .singbox, .xrayError],
                                    startAtEnd: true)
        self.watcher.onRecord = { [weak model] record, kind in
            MainActor.assumeIsolated {
                model?.handle(record, source: kind, now: Date())
            }
        }
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.watcher.poll()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() { task?.cancel(); task = nil }
}
```

- [ ] **Step 2: 验证编译**

Run: `swift build`
Expected: 构建成功。

- [ ] **Step 3: 提交**

```bash
git add Sources/V2rayNSentinel/Monitor.swift
git commit -m "feat: drive gui + sing-box + xray sources via MultiWatcher"
```

---

### Task 12: 设置界面新增内核监控项

**Files:**
- Modify: `Sources/V2rayNSentinel/SettingsView.swift`

**Interfaces:**
- Consumes: `AppModel.settings`(v2 新字段)。
- Produces: 设置界面新增「内核监控」区:总闸、突发窗口/阈值、升级冷却、聚合空闲、含 Warning 开关,均绑定 `model.settings` 并落盘。

- [ ] **Step 1: 在 SettingsView 的 Form 里加一节**

在 `Section("规则…")` 之后插入:
```swift
            Section("内核监控(sing-box / xray)") {
                Toggle("启用内核日志监控", isOn: bind(\.coreMonitoringEnabled))
                Toggle("也报 Warning 级别", isOn: bind(\.coreAlertIncludesWarning))
                Stepper("突发窗口 \(Int(model.settings.burstWindowSeconds)) 秒",
                        value: bind(\.burstWindowSeconds), in: 5...300, step: 5)
                Stepper("突发升级阈值 \(model.settings.burstThreshold) 次",
                        value: bind(\.burstThreshold), in: 2...500)
                Stepper("升级冷却 \(Int(model.settings.escalationCooldownSeconds)) 秒",
                        value: bind(\.escalationCooldownSeconds), in: 30...3600, step: 30)
                Stepper("聚合 toast 空闲 \(Int(model.settings.aggregatedToastIdleSeconds)) 秒消失",
                        value: bind(\.aggregatedToastIdleSeconds), in: 3...60)
            }
```
> `bind` 辅助已在 v1 SettingsView 中;`Int` 字段(burstThreshold)用 `bind(\.burstThreshold)`(Binding<Int>),Stepper 接受 Int。

- [ ] **Step 2: 验证编译**

Run: `swift build`
Expected: 构建成功。

- [ ] **Step 3: 提交**

```bash
git add Sources/V2rayNSentinel/SettingsView.swift
git commit -m "feat: add core-monitoring settings section"
```

---

### Task 13: 菜单栏「内核日志未开启」提示(可选)

**Files:**
- Modify: `Sources/V2rayNSentinel/MenuContent.swift`
- Modify: `Sources/AppLogic/AppModel.swift`

**Interfaces:**
- Produces: `AppModel` 暴露 `@Published var coreLoggingDetected: Bool`,由 Monitor 每次轮询发现内核源文件是否存在来置位;`MenuContent` 在 `coreMonitoringEnabled && !coreLoggingDetected` 时显示一行提示"内核日志未开启(在 v2rayN 里开启核心日志)"。

- [ ] **Step 1: AppModel 加 coreLoggingDetected 状态**

`AppModel` 加:
```swift
    @Published public private(set) var coreLoggingDetected: Bool = false
    public func setCoreLoggingDetected(_ v: Bool) { if coreLoggingDetected != v { coreLoggingDetected = v } }
```

- [ ] **Step 2: Monitor 每轮探测内核源文件是否存在并上报**

在 `Monitor` 的轮询 Task 循环体内(poll 之后)加:
```swift
                if let self {
                    let names = (try? FileManager.default.contentsOfDirectory(atPath: self.directory.path)) ?? []
                    let hasCore = names.contains { $0.hasPrefix("sbox_") || $0.hasPrefix("Verror_") }
                    self.model.setCoreLoggingDetected(hasCore)
                }
```
并给 `Monitor` 保存 `private let directory: URL`(init 中赋值)。

- [ ] **Step 3: MenuContent 显示提示**

在 `MenuContent` 的监控开关之后加:
```swift
        if model.settings.coreMonitoringEnabled && !model.coreLoggingDetected {
            Text("内核日志未开启(在 v2rayN 里开启核心日志)")
                .foregroundStyle(.orange)
        }
```

- [ ] **Step 4: 验证编译 + 全量测试**

Run: `swift build && swift test`
Expected: 构建成功;全部测试 PASS。

- [ ] **Step 5: 提交**

```bash
git add Sources/V2rayNSentinel/MenuContent.swift Sources/AppLogic/AppModel.swift Sources/V2rayNSentinel/Monitor.swift
git commit -m "feat: hint in menu when core logging is off"
```

---

### Task 14: 打包 + 端到端手动验证(灌 sing-box 格式日志)

**Files:**
- Modify: `scripts/feed-log.sh`(支持内核格式)

**Interfaces:**
- Produces: `feed-log.sh` 增加 `core` 模式,向 `<dir>/sbox_<today>.txt` 追加 sing-box 格式的连接错误行,用于验证聚合与升级。

- [ ] **Step 1: 扩展 feed-log.sh**

在 `feed-log.sh` 末尾(echo 之前)加一个分支;把 `KIND` 语义扩展:新增当 `KIND=core` 时写 sbox 文件:
```bash
if [ "$KIND" = "core" ]; then
  TARGET="${3:-172.18.0.1:7881}"
  LINE="+0530 $(date '+%Y-%m-%d %H:%M:%S') ERROR [$RANDOM 5.0s] connection: dial tcp ${TARGET}: i/o timeout"
  echo "$LINE" >> "$DIR/sbox_$(date +%Y-%m-%d).txt"
  echo "已写入(core): $LINE"
  exit 0
fi
```
(置于原 ordinary/important 分支之前。)

- [ ] **Step 2: 打包(仅构建,不运行 App)**

Run: `./scripts/make-app.sh`
Expected: 生成 `build/V2rayN Sentinel.app`。

- [ ] **Step 3: 端到端手动验证(临时目录,不碰真日志)**

1. 临时把 `SentinelApp.init` 的 `dir` 硬编码为一个测试目录 `TESTDIR`(仅调试),重新 `./scripts/make-app.sh` 并 `open`。
2. 单条:`./scripts/feed-log.sh "$TESTDIR" core 9.9.9.9:80` → 预期左上角小 toast `9.9.9.9:80  i/o timeout`;再灌几条同目标 → 同一条 toast 计数 `×N` 递增。
3. 突发:快速灌 ≥ 阈值条同目标 → 预期升级出**红色重要卡片 + 声音 + 需手动关**。
4. 不同目标各自独立聚合成各自一条。
5. 菜单栏:测试目录没有真实内核文件时看到"内核日志未开启"提示;有 `sbox_*` 后提示消失。
6. 验证完还原硬编码,重新打包。

Expected: 行为逐条符合;`swift test` 全绿。

- [ ] **Step 4: 提交**

```bash
git add scripts/feed-log.sh
git commit -m "build: feed-log.sh core mode for sing-box aggregation E2E"
```

---

## 自检(Self-Review)

**1. Spec 覆盖**
- A 监控 sbox_+Verror_、跳过 Vaccess → Task 7(LogSource.singbox/xrayError,无 Vaccess)+ Task 11 ✅
- 两格式解析 → Task 2/3 ✅
- B 默认普通+突发升级 → Task 6(Aggregator escalate)+ Task 9(handleCore)✅
- C 按目标+类型聚合 ×N → Task 5(target/kind)+ Task 6(key)+ Task 10(键控 toast)✅
- 默认参数 30s/20/300/Error/10s → Task 8(Settings.default)+ Task 6/9 引用 ✅
- 级别门槛(默认不含 Warning,可配)→ Task 9(coreAlertIncludesWarning)✅
- 与 v1 兼容(gui 不变、文件名互斥、缺文件静默)→ Task 4(默认值)+ Task 7(缺文件静默测试)+ Task 9(handle 默认 .gui)✅
- 设置新增 → Task 8 + Task 12 ✅
- "内核日志未开启"提示 → Task 13 ✅
- 只读离线不变 → 未引入任何写/网络;沿用 v1 只读 ✅

**2. 占位扫描**:无 TBD/TODO;每个代码步骤含完整代码;手动验证步骤给出具体命令与预期。

**3. 类型一致性**:`HeaderMatcher.match -> (String,LogLevel,String)?`、`LogParser(matcher:)`、`LogFileLocator.newestMatchingFile(in:pattern:)`、`LogWatcher(... filePattern:headerMatcher:)`、`SourceKind`、`LogSource`、`MultiWatcher.onRecord:(LogRecord,SourceKind)`、`ConnectionErrorInfo{target,kind}`/`ConnectionErrorParser.extract`、`AggregatorParams`/`AggregateOutcome`/`Aggregator.key`/`ingest(key:now:)`、`Settings` 新字段、`Alerting.presentAggregated`、`AppModel.handle(_:source:now:)`、`ToastManager.showOrUpdateAggregated` 在各任务间一致。

**已知取舍**:v2 内核分类以级别门槛为准(noise/importantKeywords 主要作用于 GUI 源);内核连接错误的"重要"由**突发升级**决定,而非关键词——与 spec 的聚合优先思路一致。ToastManager 键控 toast 的空闲消失用 token 防抖,避免旧计时器误关新 toast。

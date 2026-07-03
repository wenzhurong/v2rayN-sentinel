import SentinelCore

// 占位入口。SwiftPM 可执行 target 的顶层代码只允许出现在 main.swift 中,
// 故此处用 @main;Task 15 会删除本文件并由 SentinelApp(@main)接管。
@main
struct Placeholder {
    static func main() {
        print("V2rayN Sentinel \(SentinelCore.version)")
    }
}

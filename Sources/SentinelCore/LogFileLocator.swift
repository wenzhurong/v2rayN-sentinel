import Foundation

public enum LogFileLocator {
    /// 从目录文件名中选出匹配 `pattern`(不含锚点)且最大的文件名。
    /// 用 ASCII 数字类的模式,避免全角/阿拉伯数字污染 `.max()`。
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

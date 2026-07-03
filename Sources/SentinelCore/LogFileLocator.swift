import Foundation

public enum LogFileLocator {
    /// 从目录文件名中选出日期最大的 `YYYY-MM-DD.txt`。
    /// 用 `[0-9]`(仅 ASCII 数字)而非 `\d`(Unicode 数字类),
    /// 避免全角/阿拉伯数字文件名混入并因标量排序污染 `.max()`。
    public static func newestDateFile(in filenames: [String]) -> String? {
        let dated = filenames.filter {
            $0.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}\.txt$"#, options: .regularExpression) != nil
        }
        return dated.max()
    }
}

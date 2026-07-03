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

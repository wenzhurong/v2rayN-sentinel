import Foundation
import SentinelCore

/// 弹窗/声音的抽象,便于协调逻辑单测。
@MainActor
public protocol Alerting: AnyObject {
    func present(entry: HistoryEntry, important: Bool, autoDismiss: TimeInterval?)
    func playSound(named name: String)
    /// 键控聚合 toast:同 key 更新计数,否则新建。
    func presentAggregated(key: String, title: String, count: Int, autoDismiss: TimeInterval?)
}

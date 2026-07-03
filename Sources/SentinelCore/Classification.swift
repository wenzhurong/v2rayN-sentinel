public enum Classification: Equatable, Sendable {
    case ignored    // 非错误,不弹
    case ordinary   // 错误但属噪音 → 小 toast
    case important  // 升级:红色 + 声音 + 手动关闭
}

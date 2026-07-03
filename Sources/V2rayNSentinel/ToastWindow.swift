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

import AppKit

/// 播放命名的系统提示音(如 "Basso");找不到则退回系统 beep。
@MainActor
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

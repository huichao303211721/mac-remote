import Cocoa
import CoreGraphics

final class Synth {
    static let shared = Synth()

    private init() {}

    var accessible: Bool { AXIsProcessTrusted() }

    // MARK: - 键盘

    private func flags(_ b: RemoteButton) -> CGEventFlags {
        var f: CGEventFlags = []
        if b.command { f.insert(.maskCommand) }
        if b.option { f.insert(.maskAlternate) }
        if b.control { f.insert(.maskControl) }
        if b.shift { f.insert(.maskShift) }
        return f
    }

    func keyDown(_ code: CGKeyCode, flags: CGEventFlags = []) {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)
        e?.flags = flags
        e?.post(tap: .cghidEventTap)
    }

    func keyUp(_ code: CGKeyCode, flags: CGEventFlags = []) {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
        e?.flags = flags
        e?.post(tap: .cghidEventTap)
    }

    func tapKey(_ code: CGKeyCode, flags: CGEventFlags = []) {
        keyDown(code, flags: flags)
        usleep(20000)
        keyUp(code, flags: flags)
    }

    // MARK: - Fn 键（豆包输入法长按说话）

    private var fnDown = false

    func fnBegin() {
        guard !fnDown else { return }
        fnDown = true
        // 用 flagsChanged 事件把一个“裸 Fn”按下状态发出去
        if let e = CGEvent(keyboardEventSource: nil, virtualKey: 63, keyDown: true) {
            e.type = .flagsChanged
            e.flags = .maskSecondaryFn
            e.setIntegerValueField(.keyboardEventKeycode, value: 63)
            e.post(tap: .cghidEventTap)
        }
        // 同时补一个键盘事件，部分输入法只认这种
        let k = CGEvent(keyboardEventSource: nil, virtualKey: 63, keyDown: true)
        k?.flags = .maskSecondaryFn
        k?.post(tap: .cghidEventTap)
    }

    func fnEnd() {
        guard fnDown else { return }
        fnDown = false
        if let e = CGEvent(keyboardEventSource: nil, virtualKey: 63, keyDown: false) {
            e.type = .flagsChanged
            e.flags = []
            e.setIntegerValueField(.keyboardEventKeycode, value: 63)
            e.post(tap: .cghidEventTap)
        }
        let k = CGEvent(keyboardEventSource: nil, virtualKey: 63, keyDown: false)
        k?.flags = []
        k?.post(tap: .cghidEventTap)
    }

    // MARK: - 鼠标

    func moveMouse(dx: CGFloat, dy: CGFloat) {
        let cur = CGEvent(source: nil)?.location ?? .zero
        let maxP = CGDisplayBounds(CGMainDisplayID())
        var x = cur.x + dx * Store.shared.config.pad.pointerSpeed
        var y = cur.y + dy * Store.shared.config.pad.pointerSpeed
        x = min(max(x, maxP.minX + 1), maxP.maxX - 1)
        y = min(max(y, maxP.minY + 1), maxP.maxY - 1)
        let e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                        mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)
        e?.post(tap: .cghidEventTap)
    }

    func click(button: CGMouseButton = .left) {
        let p = CGEvent(source: nil)?.location ?? .zero
        let downType: CGEventType = (button == .left) ? .leftMouseDown : .rightMouseDown
        let upType: CGEventType = (button == .left) ? .leftMouseUp : .rightMouseUp
        CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: p, mouseButton: button)?
            .post(tap: .cghidEventTap)
        usleep(30000)
        CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: p, mouseButton: button)?
            .post(tap: .cghidEventTap)
    }

    func scroll(dy: Int32) {
        if let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0) {
            e.post(tap: .cghidEventTap)
        }
    }

    // MARK: - 系统媒体键（音量 / 静音 / 播放）

    enum Media: Int32 {
        case soundUp = 0
        case soundDown = 1
        case mute = 7
        case playPause = 16
        case next = 17
        case previous = 18
    }

    func mediaKey(_ k: Media) {
        postSystemKey(k, down: true)
        usleep(15000)
        postSystemKey(k, down: false)
    }

    private func postSystemKey(_ k: Media, down: Bool) {
        let flags: Int32 = down ? 0xA00 : 0xB00
        let data1 = (Int32(k.rawValue) << 16) | flags
        let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [],
                                    timestamp: 0, windowNumber: 0, context: nil,
                                    subtype: 8, data1: Int(data1), data2: -1)
        ev?.cgEvent?.post(tap: .cghidEventTap)
    }

    // MARK: - 执行

    private var repeating: DispatchSourceTimer?

    func startRepeat(_ body: @escaping () -> Void) {
        stopRepeat()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 0.25, repeating: 0.08)
        t.setEventHandler(handler: body)
        t.resume()
        repeating = t
    }

    func stopRepeat() {
        repeating?.cancel()
        repeating = nil
    }

    func perform(_ action: RemoteAction, button: RemoteButton, down: Bool) {
        Log.line("perform \(action) down=\(down) ax=\(AXIsProcessTrusted())")
        switch action {
        case .none:
            break
        case .leftClick:
            if down { click(button: .left) }
        case .rightClick:
            if down { click(button: .right) }
        case .returnKey:
            if down { tapKey(36) }
        case .escapeKey:
            if down { tapKey(53) }
        case .spaceKey:
            if down { tapKey(49) }
        case .deleteKey:
            if down { tapKey(51) }
        case .fnHold:
            if down { fnBegin() } else { fnEnd() }
        case .lockScreen:
            if down { tapKey(12, flags: [.maskControl, .maskCommand]) }
        case .appSwitcher:
            if down {
                keyDown(55, flags: .maskCommand)   // ⌘ 按住
                tapKey(48)                          // Tab
                usleep(150000)
                keyUp(55, flags: .maskCommand)
            }
        case .volumeUp:
            if down {
                mediaKey(.soundUp)
                if button.repeatWhileHeld { startRepeat { self.mediaKey(.soundUp) } } else { stopRepeat() }
            } else { stopRepeat() }
        case .volumeDown:
            if down {
                mediaKey(.soundDown)
                if button.repeatWhileHeld { startRepeat { self.mediaKey(.soundDown) } } else { stopRepeat() }
            } else { stopRepeat() }
        case .mute:
            if down { mediaKey(.mute) }
        case .playPause:
            if down { mediaKey(.playPause) }
        case .nextTrack:
            if down { mediaKey(.next) }
        case .previousTrack:
            if down { mediaKey(.previous) }
        case .customKey:
            guard let k = button.keyCode else { break }
            let f = flags(button)
            if down { keyDown(k, flags: f) } else { keyUp(k, flags: f) }
        }
    }

    private func handleContinuous(_ media: Media, button: RemoteButton, down: Bool, ptt: Bool) {
        repeating?.cancel()
        repeating = nil
        guard down else { return }
        mediaKey(media)
        guard button.repeatWhileHeld else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 0.35, repeating: 0.12)
        t.setEventHandler { [weak self] in self?.mediaKey(media) }
        t.resume()
        repeating = t
    }
}

import Cocoa
import CoreGraphics

final class Touchpad {
    static let shared = Touchpad()

    private typealias MTDeviceRef = UnsafeMutableRawPointer
    private typealias FrameCallback = @convention(c) (MTDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Void

    private var device: MTDeviceRef?
    private var startFn: ((MTDeviceRef, Int32) -> Int32)?
    private var running = false

    // 触摸状态
    private var touching = false
    private var startTime: TimeInterval = 0
    private var lastX: Double = 0
    private var lastY: Double = 0
    private var startX: Double = 0
    private var startY: Double = 0
    private var moved: Double = 0
    private var fingers = 0
    private var lastAvgY: Double = 0
    private var lastAvgX: Double = 0

    func start() {
        guard !running else { return }
        guard let h = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW) else {
            return
        }
        typealias CreateList = @convention(c) () -> CFArray?
        guard let createList = unsafeBitCast(dlsym(h, "MTDeviceCreateList"), to: CreateList.self) as CreateList?,
              let regRaw = dlsym(h, "MTRegisterContactFrameCallback"),
              let startRaw = dlsym(h, "MTDeviceStart") else { return }

        let reg = unsafeBitCast(regRaw, to: (@convention(c) (MTDeviceRef?, FrameCallback?, UnsafeMutableRawPointer?) -> Void).self)
        startFn = unsafeBitCast(startRaw, to: (@convention(c) (MTDeviceRef, Int32) -> Int32).self)

        guard let list = createList(), CFArrayGetCount(list) > 0 else { return }
        guard let d = CFArrayGetValueAtIndex(list, 0) else { return }
        device = UnsafeMutableRawPointer(mutating: d)

        reg(device, { _, data, n, _, _ in
            Touchpad.shared.frame(data: data, n: Int(n))
        }, nil)
        _ = startFn?(device!, 0)
        running = true
    }

    // 已知结构偏移：frame +0, timestamp +8, id +16, state +20,
    // normalized x +32, y +36, size +48, angle +56
    private func frame(data: UnsafeMutableRawPointer?, n: Int) {
        guard Store.shared.config.pad.enabled else { return }
        guard let p = data else {
            finishTouch()
            return
        }
        fingers = n
        if n == 0 {
            finishTouch()
            return
        }

        let base = p.assumingMemoryBound(to: UInt8.self)
        func f(_ off: Int) -> Double {
            Double(base.advanced(by: off).withMemoryRebound(to: Float.self, capacity: 1) { $0.pointee })
        }
        func i(_ off: Int) -> Int32 {
            base.advanced(by: off).withMemoryRebound(to: Int32.self, capacity: 1) { $0.pointee }
        }

        let state = i(20)
        // 只处理真正贴着的手指（3/4），抬起阶段 5/6/7 忽略
        guard state == 3 || state == 4 else {
            if n == 0 { finishTouch() }
            return
        }

        let x = f(32)
        let y = f(36)

        if !touching {
            touching = true
            startTime = CACurrentMediaTime()
            startX = x; startY = y
            lastX = x; lastY = y
            moved = 0
            lastAvgX = x; lastAvgY = y
            return
        }

        if n >= 2 {
            // 双指滚动
            let dy = y - lastAvgY
            lastAvgY = y
            lastAvgX = x
            if Store.shared.config.pad.twoFingerScroll, abs(dy) > 0.004 {
                Synth.shared.scroll(dy: Int32(-dy * 900))
            }
            moved += abs(dy)
            return
        }

        let dx = x - lastX
        let dy = y - lastY
        lastX = x; lastY = y
        moved += (dx * dx + dy * dy).squareRoot()

        if abs(dx) > 0 || abs(dy) > 0 {
            let scale = 1600.0
            Synth.shared.moveMouse(dx: CGFloat(dx * scale), dy: CGFloat(-dy * scale))
        }
    }

    private func finishTouch() {
        guard touching else { return }
        touching = false
        let dur = CACurrentMediaTime() - startTime
        if Store.shared.config.pad.tapToClick, dur < 0.28, moved < 0.02 {
            Synth.shared.click()
        }
    }
}

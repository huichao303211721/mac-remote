import Cocoa
import IOKit.hid

final class RemoteHID {
    static let shared = RemoteHID()

    var connected = false
    /// 遥控器的蓝牙名称（用于匹配 BLE 外设读取电量）
    private(set) var productName: String?
    var lastCode: UInt16?
    var learning: ((UInt16) -> Void)?
    var onCode: ((UInt16, Bool) -> Void)?   // code, isDown

    private var manager: IOHIDManager?
    private var buffer = [UInt8](repeating: 0, count: 64)

    private init() {}

    func start() {
        if #available(macOS 13.0, *) {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = m
        let match: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x004C,
            kIOHIDProductIDKey as String: 0x0315
        ]
        IOHIDManagerSetDeviceMatching(m, match as CFDictionary)
        IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, device in
            RemoteHID.shared.deviceAdded()
            _ = device
            _ = ctx
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceRemovalCallback(m, { _, _, _, _ in
            RemoteHID.shared.deviceRemoved()
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterInputReportCallback(m, { ctx, _, _, _, reportID, report, length in
            guard let ctx else { return }
            let me = Unmanaged<RemoteHID>.fromOpaque(ctx).takeUnretainedValue()
            me.handle(reportID: reportID, report: report, length: Int(length))
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshConnection()
        }
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refreshConnection()
        }
    }

    private func refreshConnection() {
        guard let m = manager else { return }
        if let set = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>, !set.isEmpty {
            connected = true
            if productName == nil {
                let d = set.first!
                if let n = IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String {
                    productName = n
                }
            }
        } else {
            connected = false
        }
        NotificationCenter.default.post(name: .remoteStateChanged, object: nil)
    }

    private func deviceAdded() {
        connected = true
        NotificationCenter.default.post(name: .remoteStateChanged, object: nil)
    }

    private func deviceRemoved() {
        connected = false
        NotificationCenter.default.post(name: .remoteStateChanged, object: nil)
    }

    private func handle(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: Int) {
        // 报告布局：[0]=0xFB 报告 ID，[1]=按键码，[2]=按下/释放（少数型号带第 3 字节）
        guard length >= 3 else { return }
        let rid = report[0]
        guard rid == 0xFB else { return }
        // 16 位合成编码：高位为第 2 字节，低位为第 3 字节（播放/暂停等键用的是低位）
        let code = (UInt16(report[1]) << 8) | UInt16(report[2])
        Log.line(String(format: "HID rid=0x%02X code=0x%04X (b1=0x%02X b2=0x%02X)", rid, code, report[1], report[2]))

        if code != 0 {
            lastCode = code
            if learning != nil {
                let cb = learning
                learning = nil
                DispatchQueue.main.async { cb?(code) }
                return
            }
            onCode?(code, true)
        } else if let lc = lastCode {
            lastCode = nil
            onCode?(lc, false)
        }
    }
}

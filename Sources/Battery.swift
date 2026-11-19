import Cocoa
import CoreBluetooth

/// 读取 Siri Remote 电量与充电状态：
/// 通过 CoreBluetooth 找到已连接的遥控器，读 Battery Service(0x180F) 的
/// Battery Level(0x2A19) 与 Battery Power State(0x2A1A)。
final class BatteryMonitor: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = BatteryMonitor()

    /// 电量 + 是否充电，nil 表示暂时读不到
    var onChange: ((Int?, Bool) -> Void)?
    private(set) var level: Int?
    private(set) var isCharging = false

    private var central: CBCentralManager?
    private var target: CBPeripheral?
    private var busy = false
    private var started = false
    private var waiters: [(Int?, Bool) -> Void] = []
    private var retries = 0
    private var lastFetch = Date.distantPast

    private var levelChar: CBCharacteristic?
    private var powerChar: CBCharacteristic?
    private var pendingLevel: Int?

    func start() {
        guard !started else { return }
        started = true
        central = CBCentralManager(delegate: self, queue: .main)
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        NotificationCenter.default.addObserver(forName: .remoteStateChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    /// 主动刷新一次；completion 会在本次读取结束时回调
    func refresh(completion: ((Int?, Bool) -> Void)? = nil, force: Bool = false) {
        if let completion { waiters.append(completion) }
        if busy { return }
        if !force, Date().timeIntervalSince(lastFetch) < 20 { return }
        lastFetch = Date()
        guard let c = central, c.state == .poweredOn else {
            finish(nil)
            return
        }
        busy = true
        levelChar = nil
        powerChar = nil
        pendingLevel = nil
        let ps = c.retrieveConnectedPeripherals(withServices: [CBUUID(string: "180F"),
                                                               CBUUID(string: "1812")])
        guard let p = pick(ps) else {
            Log.line("battery: no peripheral")
            finish(nil)
            if retries < 3 {
                retries += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.refresh(force: true) }
            }
            return
        }
        target = p
        p.delegate = self
        if p.state == .connected {
            p.discoverServices([CBUUID(string: "180F")])
        } else {
            c.connect(p, options: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.busy else { return }
            Log.line("battery: timeout")
            self.finish(nil)
        }
    }

    private func pick(_ ps: [CBPeripheral]) -> CBPeripheral? {
        if let name = RemoteHID.shared.productName,
           let p = ps.first(where: { $0.name == name }) {
            return p
        }
        return ps.first(where: { ($0.name ?? "").localizedCaseInsensitiveContains("remote") })
    }

    private func finish(_ value: Int?) {
        if let l = value {
            level = l
            retries = 0
        }
        let p = target
        target = nil
        busy = false
        levelChar = nil
        powerChar = nil
        pendingLevel = nil
        if let p, let c = central, p.state != .disconnected {
            c.cancelPeripheralConnection(p)
        }
        let charging = isCharging
        onChange?(value ?? level, charging)
        let cbs = waiters
        waiters.removeAll()
        for cb in cbs { cb(value ?? level, charging) }
    }

    /// 解析 Battery Power State(0x2A1A)：
    /// bit0-1 电池是否存在 / bit2-3 有线外接电源 / bit4-5 无线外接电源 / bit6-7 充电状态(1=充电中)
    private func decodePowerState(_ raw: UInt8) -> Bool {
        let present = Int(raw) & 0x3
        let wired = (Int(raw) >> 2) & 0x3
        let wireless = (Int(raw) >> 4) & 0x3
        let charge = (Int(raw) >> 6) & 0x3
        Log.line(String(format: "battery: power state=0x%02X present=%d wired=%d wireless=%d charge=%d",
                        Int(raw), present, wired, wireless, charge))
        // 只用「有线外接电源」位判定：本机实测拔线后 charge 位仍为 1（滞后/错误），
        // 而 wired 位立刻由 2(已接电源) 变 3(未接)，是唯一可靠的信号。
        return wired == 2
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        Log.line("battery: central state=\(c.state.rawValue)")
        if c.state == .poweredOn { refresh(force: true) }
    }

    func centralManager(_ c: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([CBUUID(string: "180F")])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Log.line("battery: connect failed \(error?.localizedDescription ?? "-")")
        finish(nil)
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if busy && target === peripheral { finish(nil) }
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == CBUUID(string: "180F") }) else {
            finish(nil)
            return
        }
        p.discoverCharacteristics([CBUUID(string: "2A19"), CBUUID(string: "2A1A")], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        let chs = s.characteristics ?? []
        levelChar = chs.first(where: { $0.uuid == CBUUID(string: "2A19") })
        powerChar = chs.first(where: { $0.uuid == CBUUID(string: "2A1A") })
        guard let lc = levelChar else {
            finish(nil)
            return
        }
        p.readValue(for: lc)
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        if ch.uuid == CBUUID(string: "2A19") {
            guard let d = ch.value, let first = d.first else {
                finish(nil)
                return
            }
            let value = Int(first)
            pendingLevel = value
            Log.line("battery: \(value)%")
            if let pc = powerChar {
                p.readValue(for: pc)
            } else {
                isCharging = false
                finish(value)
            }
            return
        }

        if ch.uuid == CBUUID(string: "2A1A") {
            if let d = ch.value, let first = d.first, error == nil {
                isCharging = decodePowerState(first)
            } else {
                // 读不到供电位时按未充电处理，避免残留上一次的充电标识
                isCharging = false
                Log.line("battery: power state unavailable")
            }
            finish(pendingLevel)
            return
        }

        finish(nil)
    }
}

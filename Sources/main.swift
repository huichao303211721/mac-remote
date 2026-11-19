import Cocoa
import ServiceManagement

enum LaunchAtLogin {
    static func set(_ on: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if on { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("launchAtLogin error: \(error)")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var windowController: MainWindowController?
    var statusItem: NSStatusItem?
    private var batteryItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(Store.shared.config.showDockIcon ? .regular : .accessory)

        let wc = MainWindowController()
        windowController = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        setupStatusItem()
        startEngine()

        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
        Log.line("launch AX=\(AXIsProcessTrusted())")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController?.showWindow(nil)
        return true
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Mac 遥控"
        let menu = NSMenu()
        menu.delegate = self
        let b = NSMenuItem(title: "电量：读取中…", action: nil, keyEquivalent: "")
        b.isEnabled = false
        menu.addItem(b)
        batteryItem = b
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "打开主界面", action: #selector(openMain), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "停止控制 / 启动控制", action: #selector(toggleControl), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        for m in menu.items { m.target = self }
        item.menu = menu
        statusItem = item
        updateStatusTitle()
    }

    /// 菜单栏标题：控制状态 + 连接标记 + 电量（充电时带闪电，低电量转橙）
    private func updateStatusTitle() {
        var t = Store.shared.config.controlEnabled ? "Mac 遥控" : "Mac 遥控（已停止）"
        if RemoteHID.shared.connected { t += " ●" }

        var color = NSColor.labelColor
        let battery = BatteryMonitor.shared
        if let lvl = battery.level {
            if battery.isCharging {
                t += " ⚡\(lvl)%"
                color = .systemGreen
            } else {
                t += " \(lvl)%"
                if lvl <= 20 { color = .systemOrange }
            }
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: NSFont.menuBarFont(ofSize: 0)
        ]
        statusItem?.button?.attributedTitle = NSAttributedString(string: t, attributes: attrs)
    }

    /// 菜单展开时刷新电量详情
    func menuWillOpen(_ menu: NSMenu) {
        let battery = BatteryMonitor.shared
        guard let lvl = battery.level else {
            batteryItem?.title = "电量：暂未读取到"
            return
        }
        var text = "电量：\(lvl)%"
        if battery.isCharging { text += "（充电中 ⚡）" }
        if let d = battery.lastRead {
            let sec = Int(Date().timeIntervalSince(d))
            let ago = sec < 60 ? "\(sec) 秒前" : (sec < 3600 ? "\(sec / 60) 分钟前" : "\(sec / 3600) 小时前")
            text += " · 更新于 \(ago)"
        }
        batteryItem?.title = text
    }

    @objc private func openMain() {
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleControl() {
        Store.shared.config.controlEnabled.toggle()
        Store.shared.save()
        updateStatusTitle()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func startEngine() {
        RemoteHID.shared.onCode = { code, down in
            guard Store.shared.config.controlEnabled else { return }
            guard let b = Store.shared.button(code: code), b.enabled else { return }
            Synth.shared.perform(b.action, button: b, down: down)
        }
        RemoteHID.shared.start()
        Touchpad.shared.start()
        BatteryMonitor.shared.start()

        NotificationCenter.default.addObserver(forName: .remoteStateChanged, object: nil, queue: .main) { _ in
            self.updateStatusTitle()
        }
        BatteryMonitor.shared.observe { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateStatusTitle() }
        }
        updateStatusTitle()
    }
}

// 维护命令：--unregister-login 用于移除系统登录项
if CommandLine.arguments.contains("--unregister-login") {
    if #available(macOS 13.0, *) {
        do { try SMAppService.mainApp.unregister(); print("unregistered") }
        catch { print("unregister failed: \(error)") }
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

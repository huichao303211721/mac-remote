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

final class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: MainWindowController?
    var statusItem: NSStatusItem?

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
        menu.addItem(NSMenuItem(title: "打开主界面", action: #selector(openMain), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "停止控制 / 启动控制", action: #selector(toggleControl), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        for m in menu.items { m.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func openMain() {
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleControl() {
        Store.shared.config.controlEnabled.toggle()
        Store.shared.save()
        statusItem?.button?.title = Store.shared.config.controlEnabled ? "Mac 遥控" : "Mac 遥控（已停止）"
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
            self.statusItem?.button?.title = RemoteHID.shared.connected ? "Mac 遥控 ●" : "Mac 遥控"
        }
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

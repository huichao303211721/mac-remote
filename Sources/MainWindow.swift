import Cocoa

final class MainWindowController: NSWindowController {
    private let sidebar = SidebarView(frame: NSRect(x: 0, y: 0, width: 240, height: 800))
    private let container = NSView(frame: NSRect(x: 240, y: 0, width: 940, height: 800))

    convenience init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 800),
                         styleMask: [.titled, .closable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "Mac 遥控"
        w.titlebarAppearsTransparent = true
        w.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1)
        w.isReleasedWhenClosed = false
        self.init(window: w)
        w.center()
        setup()
    }

    private func setup() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        sidebar.frame = NSRect(x: 0, y: 0, width: 240, height: content.bounds.height)
        container.frame = NSRect(x: 240, y: 0, width: content.bounds.width - 240, height: content.bounds.height)
        content.addSubview(sidebar)
        content.addSubview(container)
        sidebar.onSelect = { [weak self] idx in self?.show(idx) }
        sidebar.select(0)
    }

    func show(_ idx: Int) {
        container.subviews.forEach { $0.removeFromSuperview() }
        let h = container.bounds.height, w = container.bounds.width
        var v: NSView
        switch idx {
        case 0: v = MappingSection(frame: NSRect(x: 0, y: 0, width: w, height: h))
        case 3: v = DeviceSection(frame: NSRect(x: 0, y: 0, width: w, height: h))
        case 4: v = VoiceSection(frame: NSRect(x: 0, y: 0, width: w, height: h))
        case 5: v = AboutSection(frame: NSRect(x: 0, y: 0, width: w, height: h))
        default: v = PlaceholderSection(frame: NSRect(x: 0, y: 0, width: w, height: h),
                                       text: idx == 1 ? "场景" : "快捷指令")
        }
        container.addSubview(v)
    }
}

// MARK: - 映射页

final class MappingSection: NSView {
    private let remote = RemoteShapeView(frame: NSRect(x: 24, y: 24, width: 300, height: 700))
    private let cardHost = NSView()
    private let batteryBox = NSView()
    private let batteryIcon = BatteryGaugeView(frame: NSRect(x: 12, y: 6, width: 26, height: 17))
    private let batteryLabel = label("读取中…", size: 12, color: NSColor(calibratedWhite: 0.93, alpha: 1))
    private var current = "siri"

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1).cgColor

        let title = label("映射", size: 18, color: NSColor(calibratedWhite: 0.95, alpha: 1))
        title.frame = NSRect(x: 24, y: frame.height - 56, width: 200, height: 22)
        addSubview(title)

        // 遥控器电量
        batteryBox.frame = NSRect(x: 84, y: frame.height - 102, width: 180, height: 28)
        batteryBox.wantsLayer = true
        batteryBox.layer?.backgroundColor = NSColor(calibratedWhite: 0.20, alpha: 1).cgColor
        batteryBox.layer?.cornerRadius = 14
        batteryBox.layer?.borderWidth = 1
        batteryBox.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.08).cgColor
        addSubview(batteryBox)

        batteryBox.addSubview(batteryIcon)

        batteryLabel.frame = NSRect(x: 46, y: 6, width: 128, height: 16)
        batteryLabel.font = .systemFont(ofSize: 12, weight: .medium)
        batteryBox.addSubview(batteryLabel)

        BatteryMonitor.shared.onChange = { [weak self] lvl, charging in
            DispatchQueue.main.async { self?.updateBattery(lvl, charging: charging) }
        }
        updateBattery(BatteryMonitor.shared.level, charging: BatteryMonitor.shared.isCharging)
        BatteryMonitor.shared.start()
        BatteryMonitor.shared.refresh()

        remote.frame = NSRect(x: 24, y: 20, width: 300, height: frame.height - 158)
        remote.onPick = { [weak self] id in
            self?.current = id
            self?.remote.selectedID = id
            self?.rebuildCard()
        }
        remote.selectedID = current
        addSubview(remote)

        cardHost.frame = NSRect(x: 340, y: 20, width: frame.width - 380, height: frame.height - 100)
        addSubview(cardHost)

        rebuildCard()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateBattery(_ level: Int?, charging: Bool) {
        batteryIcon.level = level
        batteryIcon.charging = charging
        guard let level else {
            batteryLabel.stringValue = "电量 —"
            batteryLabel.textColor = NSColor(calibratedWhite: 0.6, alpha: 1)
            return
        }
        if charging {
            batteryLabel.stringValue = "充电中 \(level)%"
            batteryLabel.textColor = NSColor.systemGreen
        } else {
            batteryLabel.stringValue = "遥控器 \(level)%"
            batteryLabel.textColor = level <= 20 ? NSColor.systemOrange : NSColor(calibratedWhite: 0.93, alpha: 1)
        }
    }

    private func rebuildCard() {
        cardHost.subviews.forEach { $0.removeFromSuperview() }
        guard var b = Store.shared.button(id: current) else { return }
        let cardW = cardHost.bounds.width

        let box = NSView(frame: NSRect(x: 0, y: 0, width: cardW, height: cardHost.bounds.height))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(calibratedWhite: 0.17, alpha: 1).cgColor
        box.layer?.cornerRadius = 14
        cardHost.addSubview(box)

        var y = box.bounds.height - 40

        let name = label(b.title, size: 15, color: NSColor(calibratedWhite: 0.95, alpha: 1))
        name.frame = NSRect(x: 24, y: y, width: 300, height: 20)
        box.addSubview(name)

        let code = b.code.map { String(format: "HID 0x%02X", $0) } ?? "尚未学习遥控器按键"
        let sub = label(b.action.title + " · " + code, size: 11, color: NSColor(calibratedWhite: 0.5, alpha: 1))
        sub.frame = NSRect(x: 24, y: y - 20, width: 400, height: 16)
        box.addSubview(sub)

        y -= 70
        let actionTitle = label("按键动作", size: 12)
        actionTitle.frame = NSRect(x: 24, y: y, width: 120, height: 18)
        box.addSubview(actionTitle)

        let popup = NSPopUpButton(frame: NSRect(x: 24, y: y - 34, width: 260, height: 26))
        for a in RemoteAction.allCases { popup.addItem(withTitle: a.title) }
        popup.selectItem(withTitle: b.action.title)
        popup.target = self
        popup.action = #selector(actionChanged(_:))
        box.addSubview(popup)
        y -= 90

        if b.action == .customKey {
            let t = label("按键码（如 36 = 回车）", size: 12)
            t.frame = NSRect(x: 24, y: y, width: 200, height: 18)
            box.addSubview(t)
            let field = NSTextField(frame: NSRect(x: 24, y: y - 28, width: 90, height: 24))
            field.stringValue = b.keyCode.map(String.init) ?? ""
            field.placeholderString = "36"
            field.target = self
            field.action = #selector(keyCodeChanged(_:))
            box.addSubview(field)
            y -= 70
        }

        let repeatBox = NSButton(checkboxWithTitle: "按住时连续触发（适合音量）", target: self, action: #selector(repeatChanged(_:)))
        repeatBox.state = b.repeatWhileHeld ? .on : .off
        repeatBox.frame = NSRect(x: 24, y: y - 4, width: 260, height: 20)
        box.addSubview(repeatBox)
        y -= 46

        let learn = NSButton(title: "学习遥控器按键", target: self, action: #selector(learnPressed(_:)))
        learn.bezelStyle = .rounded
        learn.frame = NSRect(x: 24, y: y - 6, width: 150, height: 28)
        box.addSubview(learn)

        let learnHint = label("点它，然后在遥控器上按下要绑定的键", size: 11, color: NSColor(calibratedWhite: 0.5, alpha: 1))
        learnHint.frame = NSRect(x: 186, y: y, width: 320, height: 16)
        box.addSubview(learnHint)
        y -= 60

        let enable = NSButton(checkboxWithTitle: "启用此按键", target: self, action: #selector(enabledChanged(_:)))
        enable.state = b.enabled ? .on : .off
        enable.frame = NSRect(x: 24, y: y, width: 180, height: 20)
        box.addSubview(enable)
    }

    @objc private func actionChanged(_ sender: NSPopUpButton) {
        guard var b = Store.shared.button(id: current),
              let a = RemoteAction.allCases.first(where: { $0.title == sender.titleOfSelectedItem }) else { return }
        b.action = a
        Store.shared.update(b)
        rebuildCard()
    }

    @objc private func keyCodeChanged(_ sender: NSTextField) {
        guard var b = Store.shared.button(id: current) else { return }
        b.keyCode = UInt16(sender.stringValue) ?? nil
        Store.shared.update(b)
        rebuildCard()
    }

    @objc private func repeatChanged(_ sender: NSButton) {
        guard var b = Store.shared.button(id: current) else { return }
        b.repeatWhileHeld = (sender.state == .on)
        Store.shared.update(b)
    }

    @objc private func enabledChanged(_ sender: NSButton) {
        guard var b = Store.shared.button(id: current) else { return }
        b.enabled = (sender.state == .on)
        Store.shared.update(b)
    }

    @objc private func learnPressed(_ sender: NSButton) {
        sender.title = "请按遥控器上的键…"
        RemoteHID.shared.learning = { [weak self] code in
            guard let self, var b = Store.shared.button(id: self.current) else { return }
            b.code = code
            Store.shared.update(b)
            self.rebuildCard()
            self.remote.flashID = self.current
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.remote.flashID = nil }
        }
    }
}

// MARK: - 设备设置页

final class DeviceSection: NSView {
    private var statusLabels: [String: NSTextField] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1).cgColor

        let title = label("设备设置", size: 18, color: NSColor(calibratedWhite: 0.95, alpha: 1))
        title.frame = NSRect(x: 24, y: frame.height - 56, width: 200, height: 22)
        addSubview(title)

        var y = frame.height - 120
        let x: CGFloat = 24, w = frame.width - 48

        // 权限
        let perm = card("权限", "需要“辅助功能”和“输入监控”，Voxa 有的我们也一样")
        perm.frame = NSRect(x: x, y: y - 100, width: w, height: 100)
        let axLabel = label("辅助功能：检测中…")
        axLabel.frame = NSRect(x: 18, y: 44, width: 420, height: 18)
        perm.addSubview(axLabel)
        statusLabels["ax"] = axLabel
        let axBtn = NSButton(title: "去授权", target: self, action: #selector(openAX))
        axBtn.bezelStyle = .rounded
        axBtn.frame = NSRect(x: perm.bounds.width - 110, y: 40, width: 90, height: 28)
        axBtn.autoresizingMask = [.minXMargin]
        perm.addSubview(axBtn)
        let imLabel = label("输入监控：检测遥控器连接状态")
        imLabel.frame = NSRect(x: 18, y: 18, width: 420, height: 18)
        perm.addSubview(imLabel)
        statusLabels["im"] = imLabel
        addSubview(perm)
        y -= 116

        // 遥控器
        let remoteCard = card("遥控器", "Siri Remote（A2854，VID 0x004C / PID 0x0315）")
        remoteCard.frame = NSRect(x: x, y: y - 88, width: w, height: 88)
        let rs = label("连接状态：检测中…", size: 12, color: .white)
        rs.frame = NSRect(x: 18, y: 32, width: 420, height: 18)
        remoteCard.addSubview(rs)
        statusLabels["remote"] = rs
        addSubview(remoteCard)
        y -= 104

        // 触控板
        let padCard = card("触控板", "手指在圆形触控区移动 = 移动指针")
        padCard.frame = NSRect(x: x, y: y - 130, width: w, height: 130)
        let padToggle = NSButton(checkboxWithTitle: "启用触控板", target: self, action: #selector(padToggled(_:)))
        padToggle.state = Store.shared.config.pad.enabled ? .on : .off
        padToggle.frame = NSRect(x: 18, y: 74, width: 160, height: 20)
        padCard.addSubview(padToggle)

        let tapToggle = NSButton(checkboxWithTitle: "轻点 = 鼠标左键", target: self, action: #selector(tapToggled(_:)))
        tapToggle.state = Store.shared.config.pad.tapToClick ? .on : .off
        tapToggle.frame = NSRect(x: 18, y: 48, width: 200, height: 20)
        padCard.addSubview(tapToggle)

        let scrollToggle = NSButton(checkboxWithTitle: "双指滑动 = 滚动", target: self, action: #selector(scrollToggled(_:)))
        scrollToggle.state = Store.shared.config.pad.twoFingerScroll ? .on : .off
        scrollToggle.frame = NSRect(x: 18, y: 22, width: 200, height: 20)
        padCard.addSubview(scrollToggle)

        let spd = label("指针速度", size: 12)
        spd.frame = NSRect(x: 260, y: 74, width: 80, height: 18)
        padCard.addSubview(spd)
        let slider = NSSlider(value: Store.shared.config.pad.pointerSpeed, minValue: 0.3, maxValue: 3,
                              target: self, action: #selector(speedChanged(_:)))
        slider.frame = NSRect(x: 330, y: 74, width: 200, height: 20)
        padCard.addSubview(slider)
        addSubview(padCard)
        y -= 146

        // 通用
        let gen = card("通用")
        gen.frame = NSRect(x: x, y: y - 70, width: w, height: 70)
        let login = NSButton(checkboxWithTitle: "开机时自动启动", target: self, action: #selector(loginToggled(_:)))
        login.state = Store.shared.config.launchAtLogin ? .on : .off
        login.frame = NSRect(x: 18, y: 28, width: 200, height: 20)
        gen.addSubview(login)
        addSubview(gen)

        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func refresh() {
        statusLabels["ax"]?.stringValue = Synth.shared.accessible ? "辅助功能：已授权" : "辅助功能：未授权"
        statusLabels["im"]?.stringValue = RemoteHID.shared.connected ? "输入监控：正常（能读到按键）" : "输入监控：未收到数据（请在系统设置里允许）"
        statusLabels["remote"]?.stringValue = RemoteHID.shared.connected ? "连接状态：已连接" : "连接状态：未连接（去系统设置 › 蓝牙）"
    }

    @objc private func openAX() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func padToggled(_ s: NSButton) { Store.shared.config.pad.enabled = (s.state == .on); Store.shared.save() }
    @objc private func tapToggled(_ s: NSButton) { Store.shared.config.pad.tapToClick = (s.state == .on); Store.shared.save() }
    @objc private func scrollToggled(_ s: NSButton) { Store.shared.config.pad.twoFingerScroll = (s.state == .on); Store.shared.save() }
    @objc private func speedChanged(_ s: NSSlider) { Store.shared.config.pad.pointerSpeed = s.doubleValue; Store.shared.save() }
    @objc private func loginToggled(_ s: NSButton) {
        Store.shared.config.launchAtLogin = (s.state == .on)
        Store.shared.save()
        LaunchAtLogin.set(s.state == .on)
    }
}

// MARK: - 语音页

final class VoiceSection: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1).cgColor
        let title = label("语音", size: 18, color: NSColor(calibratedWhite: 0.95, alpha: 1))
        title.frame = NSRect(x: 24, y: frame.height - 56, width: 200, height: 22)
        addSubview(title)

        let box = card("按住 Siri 键说话", "和它在系统里的做法一样：Siri 键按住时，我们替你按住 Fn；豆包输入法设成“长按模式 = fn”，松手就出字。")
        box.frame = NSRect(x: 24, y: frame.height - 300, width: frame.width - 48, height: 220)
        var y = box.bounds.height - 62
        for line in ["1. 豆包输入法 → 语音输入 → 长按模式设为 fn（不要改成别的键）",
                     "2. 光标先放进一个能打字的输入框",
                     "3. 按住遥控器 Siri 键说话，说完松手，字会自动打出来",
                     "4. 声音从 Mac 的麦克风收，不用装 PacketLogger"] {
            let l = label(line, size: 12, color: NSColor(calibratedWhite: 0.8, alpha: 1))
            l.frame = NSRect(x: 18, y: y, width: box.bounds.width - 36, height: 18)
            l.lineBreakMode = .byTruncatingTail
            box.addSubview(l)
            y -= 30
        }
        addSubview(box)

        let test = NSButton(title: "打开豆包输入法设置", target: self, action: #selector(openDoubao))
        test.bezelStyle = .rounded
        test.frame = NSRect(x: 24, y: frame.height - 350, width: 170, height: 28)
        addSubview(test)

        let fnTest = NSButton(title: "测试按住 Fn 3 秒", target: self, action: #selector(testFn))
        fnTest.bezelStyle = .rounded
        fnTest.frame = NSRect(x: 204, y: frame.height - 350, width: 170, height: 28)
        addSubview(fnTest)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func openDoubao() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Library/Input Methods/DoubaoIme.app"))
    }

    @objc private func testFn() {
        Synth.shared.fnBegin()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { Synth.shared.fnEnd() }
    }
}

// MARK: - 关于 / 更新

final class AboutSection: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1).cgColor
        let title = label("软件更新", size: 18, color: NSColor(calibratedWhite: 0.95, alpha: 1))
        title.frame = NSRect(x: 24, y: frame.height - 56, width: 200, height: 22)
        addSubview(title)

        let box = card("遥控器 1.0", "自建版本 · 触控 + 音量 + 静音 + Siri 键语音")
        box.frame = NSRect(x: 24, y: frame.height - 200, width: frame.width - 48, height: 120)
        let l = label("本地构建，没有联网检查更新。需要改功能跟我说就行。", size: 12, color: NSColor(calibratedWhite: 0.6, alpha: 1))
        l.frame = NSRect(x: 18, y: 40, width: 400, height: 18)
        box.addSubview(l)
        addSubview(box)
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class PlaceholderSection: NSView {
    init(frame: NSRect, text: String) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1).cgColor
        let title = label(text, size: 18, color: NSColor(calibratedWhite: 0.95, alpha: 1))
        title.frame = NSRect(x: 24, y: frame.height - 56, width: 200, height: 22)
        addSubview(title)
        let hint = label("这一版先做核心：触控、按键、语音。这个页面现在还没有内容。", size: 12, color: NSColor(calibratedWhite: 0.55, alpha: 1))
        hint.frame = NSRect(x: 24, y: frame.height - 96, width: 500, height: 18)
        addSubview(hint)
    }
    required init?(coder: NSCoder) { fatalError() }
}

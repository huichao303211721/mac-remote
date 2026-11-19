import Cocoa
import SceneKit

// MARK: - 侧边栏

final class SidebarView: NSView {
    var onSelect: ((Int) -> Void)?
    private(set) var selected = 0
    private var rows: [SidebarRow] = []
    let items = ["映射", "场景", "快捷指令", "设备设置", "语音", "软件更新"]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 1).cgColor
        var y = frame.height - 96
        for (i, t) in items.enumerated() {
            let row = SidebarRow(title: t, index: i)
            row.onClick = { [weak self] idx in self?.select(idx) }
            row.frame = NSRect(x: 12, y: y, width: frame.width - 24, height: 34)
            addSubview(row)
            rows.append(row)
            y -= 38
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func select(_ idx: Int) {
        selected = idx
        for r in rows { r.isSelected = (r.index == idx) }
        onSelect?(idx)
    }
}

final class SidebarRow: NSView {
    let index: Int
    var onClick: ((Int) -> Void)?
    private let label = NSTextField(labelWithString: "")
    private var tracking: NSTrackingArea?

    var isSelected = false {
        didSet { needsDisplay = true }
    }

    init(title: String, index: Int) {
        self.index = index
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        label.stringValue = title
        label.font = .systemFont(ofSize: 13)
        label.textColor = NSColor(calibratedWhite: 0.85, alpha: 1)
        label.frame = NSRect(x: 14, y: 8, width: 180, height: 18)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            NSColor(calibratedRed: 0.20, green: 0.36, blue: 0.95, alpha: 0.85).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
    }

    override func mouseDown(with event: NSEvent) { onClick?(index) }
    override func updateTrackingAreas() {
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        if let t = tracking { addTrackingArea(t) }
    }
    override func mouseEntered(with event: NSEvent) {
        if !isSelected { layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.06).cgColor }
    }
    override func mouseExited(with event: NSEvent) {
        if !isSelected { layer?.backgroundColor = NSColor.clear.cgColor }
    }
}

// MARK: - 遥控器模型

final class RemoteShapeView: NSView {
    var onPick: ((String) -> Void)?
    var selectedID: String? { didSet { refreshHighlight() } }
    var flashID: String? { didSet { refreshHighlight() } }

    private let scn = SCNView()
    private let pivot = SCNNode()
    private var keyNodes: [String: SCNNode] = [:]
    private var yaw: CGFloat = 0.0
    private var modelRoot: SCNNode?
    private var pitch: CGFloat = 0.0
    private var lastPoint = NSPoint.zero
    private var dragged = false

    private let keyIDs: Set<String> = ["center", "back", "tv", "play", "mute",
                                       "volumeUp", "volumeDown", "power", "siri"]

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        scn.frame = bounds
    }

    // MARK: - 场景搭建

    private func setup() {
        wantsLayer = true
        scn.frame = bounds
        scn.autoresizingMask = [.width, .height]
        scn.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        scn.antialiasingMode = .multisampling4X
        scn.preferredFramesPerSecond = 60
        scn.allowsCameraControl = false
        scn.rendersContinuously = true
        addSubview(scn)
        buildScene()
        refreshHighlight()
    }

    private func metal(_ c: NSColor, rough: CGFloat = 0.34, metalness: CGFloat = 0.55) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = c
        m.metalness.contents = metalness
        m.roughness.contents = rough
        return m
    }

    private func glossyBlack() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(calibratedWhite: 0.075, alpha: 1)
        m.metalness.contents = 0.25
        m.roughness.contents = 0.22
        m.emission.contents = NSColor.black
        return m
    }

    private func glyph(_ name: String, size: CGFloat, color: NSColor = .white) -> SCNPlane? {
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let tinted = img.withSymbolConfiguration(cfg) else { return nil }
        let plane = SCNPlane(width: tinted.size.width / 24, height: tinted.size.height / 24)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = tinted
        m.transparency = 1
        m.isDoubleSided = true
        m.blendMode = .alpha
        plane.firstMaterial = m
        return plane
    }

    private func environmentImage() -> NSImage {
        let size = NSSize(width: 1024, height: 512)
        let img = NSImage(size: size)
        img.lockFocus()
        // 底色：中性灰渐变
        if let g = NSGradient(colorsAndLocations:
            (NSColor(calibratedWhite: 0.62, alpha: 1), 0.0),
            (NSColor(calibratedWhite: 0.42, alpha: 1), 0.35),
            (NSColor(calibratedWhite: 0.16, alpha: 1), 0.70),
            (NSColor(calibratedWhite: 0.30, alpha: 1), 1.0)) {
            g.draw(in: NSRect(origin: .zero, size: size), angle: -90)
        }
        // 顶部大柔光箱
        NSColor(calibratedWhite: 1.0, alpha: 0.95).setFill()
        NSBezierPath(roundedRect: NSRect(x: 40, y: 330, width: 420, height: 150),
                     xRadius: 60, yRadius: 60).fill()
        // 右侧竖直灯条（金属上会形成一道亮线）
        NSColor(calibratedWhite: 1.0, alpha: 0.75).setFill()
        NSBezierPath(roundedRect: NSRect(x: 700, y: 150, width: 70, height: 330),
                     xRadius: 34, yRadius: 34).fill()
        // 左侧弱反光
        NSColor(calibratedWhite: 0.9, alpha: 0.35).setFill()
        NSBezierPath(roundedRect: NSRect(x: 520, y: 60, width: 160, height: 90),
                     xRadius: 40, yRadius: 40).fill()
        img.unlockFocus()
        return img
    }

    private func buildScene() {
        let scene = SCNScene()
        scn.scene = scene
        scn.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1)

        scene.lightingEnvironment.contents = environmentImage()
        scene.lightingEnvironment.intensity = 1.05

        scene.rootNode.addChildNode(pivot)

        // 官方 Siri Remote 3D 模型（USDZ），1:1 复刻
        let bodyW: CGFloat = 4.6
        let bodyH: CGFloat = 17.5
        _ = bodyW

        if let url = Bundle.main.url(forResource: "SiriRemote", withExtension: "usdz"),
           let src = try? SCNScene(url: url, options: nil) {
            let holder = SCNNode()
            for c in src.rootNode.childNodes { holder.addChildNode(c.clone()) }
            let bb = holder.boundingBox
            let cx = (bb.min.x + bb.max.x) / 2
            let cy = (bb.min.y + bb.max.y) / 2
            let cz = (bb.min.z + bb.max.z) / 2

            let inner = SCNNode()
            inner.position = SCNVector3(-cx, -cy, -cz)
            for c in holder.childNodes { inner.addChildNode(c) }
            // 模型长轴为 Z、按键面朝 +Y：绕 X 转 90° 立起来并让按键面朝 +Z
            inner.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            let k = Float(bodyH) / Float(bb.max.z - bb.min.z)
            inner.scale = SCNVector3(k, k, k)

            let model = SCNNode()
            model.name = "body"
            model.addChildNode(inner)
            pivot.addChildNode(model)
            modelRoot = model
            Log.line("usdz loaded scale=\(k)")
        } else {
            buildProceduralRemote(pivot, bodyW: bodyW, bodyH: bodyH)
            Log.line("usdz missing -> procedural model")
        }

        // 相机
        let camera = SCNCamera()
        camera.fieldOfView = 32
        camera.zNear = 1
        camera.zFar = 400
        camera.wantsHDR = false
        let camNode = SCNNode()
        camNode.camera = camera
        camNode.position = SCNVector3(0, 0, 36)
        scene.rootNode.addChildNode(camNode)
        scn.pointOfView = camNode

        // 灯光
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = NSColor(calibratedWhite: 0.55, alpha: 1)
        ambient.intensity = 1250
        let ambNode = SCNNode()
        ambNode.light = ambient
        scene.rootNode.addChildNode(ambNode)

        let keyLight = SCNLight()
        keyLight.type = .directional
        keyLight.color = NSColor.white
        keyLight.intensity = 2200
        let keyNode = SCNNode()
        keyNode.light = keyLight
        keyNode.position = SCNVector3(9, 14, 26)
        keyNode.eulerAngles = SCNVector3(-0.5, 0.5, 0)
        scene.rootNode.addChildNode(keyNode)

        let rim = SCNLight()
        rim.type = .directional
        rim.color = NSColor(calibratedRed: 0.75, green: 0.8, blue: 1, alpha: 1)
        rim.intensity = 1400
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.position = SCNVector3(-16, 6, -18)
        rimNode.eulerAngles = SCNVector3(0.4, -0.6, 0)
        scene.rootNode.addChildNode(rimNode)

        applyOrientation()
    }

    private func applyOrientation() {
        pivot.eulerAngles = SCNVector3(Float(pitch), Float(yaw), 0)
    }

    // MARK: - 高亮

    private func refreshHighlight() {
        for (id, node) in keyNodes {
            let hot = (id == selectedID || id == flashID || (id == "pill" && (selectedID == "volumeUp" || selectedID == "volumeDown" || flashID == "volumeUp" || flashID == "volumeDown")))
            let color = hot ? NSColor(calibratedRed: 0.24, green: 0.52, blue: 1.0, alpha: 1) : NSColor.black
            if let mats = node.geometry?.materials {
                for m in mats {
                    m.emission.contents = color
                    if hot {
                        m.emission.intensity = 0.55
                    } else {
                        m.emission.intensity = 0.0
                    }
                }
            }
        }
    }

    // MARK: - 交互

    override func mouseDown(with event: NSEvent) {
        lastPoint = convert(event.locationInWindow, from: nil)
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let dx = p.x - lastPoint.x
        let dy = p.y - lastPoint.y
        if abs(dx) + abs(dy) > 1.5 { dragged = true }
        yaw += dx * 0.012
        pitch = min(max(pitch - dy * 0.010, -0.9), 0.9)
        lastPoint = p
        applyOrientation()
    }

    override func mouseUp(with event: NSEvent) {
        guard !dragged else { return }
        let p = convert(event.locationInWindow, from: nil)
        let hits = scn.hitTest(p, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue])
        for h in hits {
            var n: SCNNode? = h.node
            var inside = false
            while let cur = n {
                if cur === modelRoot { inside = true; break }
                n = cur.parent
            }
            if !inside { continue }
            let local = pivot.convertPosition(h.worldCoordinates, from: nil)
            if let id = classify(Float(local.x), Float(local.y)) { onPick?(id); return }
        }
    }

    /// 按 3D 模型上的落点换算成按键 id
    private func classify(_ x: Float, _ y: Float) -> String? {
        func dist(_ ax: Float, _ ay: Float) -> Float {
            let dx = x - ax, dy = y - ay
            return (dx * dx + dy * dy).squareRoot()
        }
        if dist(1.31, 7.94) < 0.85 { return "power" }
        if dist(0, 5.46) < 2.18 { return "center" }
        if dist(-1.05, 2.13) < 0.85 { return "back" }
        if dist(1.05, 2.13) < 0.85 { return "tv" }
        if dist(-1.05, 0.21) < 0.85 { return "play" }
        if dist(-1.05, -1.63) < 0.85 { return "mute" }
        if abs(x - 1.05) < 0.9 && y > -2.55 && y < 1.25 {
            return y > -0.66 ? "volumeUp" : "volumeDown"
        }
        if x > 2.0 && y > 0.5 && y < 4.2 { return "siri" }
        return nil
    }

    /// 没有官方 USDZ 时的程序化替代模型（开源仓库不包含 Apple 版权模型）
    private func buildProceduralRemote(_ pivot: SCNNode, bodyW: CGFloat, bodyH: CGFloat) {
        let body = SCNBox(width: bodyW, height: bodyH, length: 1.25, chamferRadius: 0.62)
        body.materials = [metal(NSColor(calibratedWhite: 0.72, alpha: 1), rough: 0.55, metalness: 0.35)]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.name = "body"
        pivot.addChildNode(bodyNode)
        modelRoot = bodyNode

        func disc(_ x: Float, _ y: Float, _ r: CGFloat, _ color: NSColor) {
            let cyl = SCNCylinder(radius: r, height: 0.10)
            cyl.radialSegmentCount = 48
            cyl.materials = [metal(color, rough: 0.22, metalness: 0.12)]
            let node = SCNNode(geometry: cyl)
            node.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            node.position = SCNVector3(x, y, 0.68)
            pivot.addChildNode(node)
        }

        // 触控盘
        disc(0, 5.46, 2.18, NSColor(calibratedWhite: 0.10, alpha: 1))

        // 返回 / TV / 播放 / 静音
        disc(-1.05, 2.13, 0.85, NSColor(calibratedWhite: 0.16, alpha: 1))
        disc(1.05, 2.13, 0.85, NSColor(calibratedWhite: 0.16, alpha: 1))
        disc(-1.05, 0.21, 0.85, NSColor(calibratedWhite: 0.16, alpha: 1))
        disc(-1.05, -1.63, 0.85, NSColor(calibratedWhite: 0.16, alpha: 1))

        // 音量胶囊
        let pill = SCNBox(width: 1.35, height: 3.8, length: 0.10, chamferRadius: 0.62)
        pill.materials = [metal(NSColor(calibratedWhite: 0.16, alpha: 1), rough: 0.22, metalness: 0.12)]
        let pillNode = SCNNode(geometry: pill)
        pillNode.position = SCNVector3(1.05, -0.65, 0.68)
        pillNode.name = "pill"
        pivot.addChildNode(pillNode)

        // 电源键（顶部右侧）
        disc(1.31, 7.94, 0.35, NSColor(calibratedWhite: 0.30, alpha: 1))

        // 右侧 Siri 键
        let siri = SCNBox(width: 0.16, height: 2.6, length: 0.9, chamferRadius: 0.08)
        siri.materials = [metal(NSColor(calibratedWhite: 0.62, alpha: 1), rough: 0.6, metalness: 0.2)]
        let siriNode = SCNNode(geometry: siri)
        siriNode.position = SCNVector3(2.32, 2.4, 0)
        pivot.addChildNode(siriNode)

        // 按键符号
        func symbol(_ name: String, _ x: Float, _ y: Float, _ size: CGFloat) {
            guard let plane = glyph(name, size: size, color: .white)
            else { return }
            let node = SCNNode(geometry: plane)
            node.position = SCNVector3(x, y, 0.78)
            pivot.addChildNode(node)
        }
        symbol("chevron.left", -1.05, 2.13, 19)
        symbol("tv", 1.05, 2.13, 17)
        symbol("playpause.fill", -1.05, 0.21, 18)
        symbol("speaker.slash.fill", -1.05, -1.63, 16)
        symbol("plus", 1.05, 0.55, 17)
        symbol("minus", 1.05, -1.85, 17)
        symbol("power", 1.31, 7.94, 12)
    }

    private func resolveKeyID(_ node: SCNNode) -> String? {
        var n: SCNNode? = node
        while let cur = n {
            if let nm = cur.name, keyIDs.contains(nm) || nm == "pill" { return nm }
            n = cur.parent
        }
        return nil
    }
}

// MARK: - 通用小控件

func card(_ title: String, _ subtitle: String? = nil) -> NSView {
    let v = NSView()
    v.wantsLayer = true
    v.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
    v.layer?.cornerRadius = 12
    let t = NSTextField(labelWithString: title)
    t.font = .systemFont(ofSize: 13, weight: .semibold)
    t.textColor = NSColor(calibratedWhite: 0.92, alpha: 1)
    t.frame = NSRect(x: 18, y: 0, width: 300, height: 18)
    v.addSubview(t)
    if let sub = subtitle {
        let s = NSTextField(labelWithString: sub)
        s.font = .systemFont(ofSize: 11)
        s.textColor = NSColor(calibratedWhite: 0.55, alpha: 1)
        s.frame = NSRect(x: 18, y: -18, width: 420, height: 16)
        v.addSubview(s)
    }
    return v
}

func label(_ text: String, size: CGFloat = 12, color: NSColor = NSColor(calibratedWhite: 0.75, alpha: 1)) -> NSTextField {
    let t = NSTextField(labelWithString: text)
    t.font = .systemFont(ofSize: size)
    t.textColor = color
    return t
}

func toggle(_ on: Bool, action: Selector, target: AnyObject) -> NSButton {
    let b = NSButton(checkboxWithTitle: "", target: target, action: action)
    b.state = on ? .on : .off
    b.setButtonType(.switch)
    return b
}

// MARK: - 电量小电池图标

final class BatteryGaugeView: NSView {
    var level: Int? { didSet { needsDisplay = true } }
    var charging: Bool = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let alpha: CGFloat = level == nil ? 0.35 : 0.95
        let stroke = NSColor(calibratedWhite: 0.88, alpha: alpha)
        let bodyRect = NSRect(x: 1, y: 3, width: 22, height: 11)

        let body = NSBezierPath(roundedRect: bodyRect, xRadius: 3, yRadius: 3)
        body.lineWidth = 1
        stroke.setStroke()
        body.stroke()

        let tip = NSBezierPath(roundedRect: NSRect(x: 23.6, y: 6, width: 2.4, height: 5), xRadius: 1, yRadius: 1)
        stroke.setFill()
        tip.fill()

        guard let level else { return }
        let inner = bodyRect.insetBy(dx: 2, dy: 2)
        let w = max(0, inner.width * CGFloat(min(max(level, 0), 100)) / 100)
        if charging {
            let fillRect = NSRect(x: inner.minX, y: inner.minY, width: max(w, inner.width * 0.18), height: inner.height)
            NSColor.systemGreen.setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: 1.5, yRadius: 1.5).fill()
            drawBolt(in: bodyRect)
            return
        }
        guard w > 0.5 else { return }
        let color: NSColor = level <= 20 ? .systemOrange : NSColor(calibratedWhite: 0.92, alpha: 1)
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: w, height: inner.height),
                     xRadius: 1.5, yRadius: 1.5).fill()
    }

    private func drawBolt(in rect: NSRect) {
        let bolt = NSBezierPath()
        let cx = rect.midX, cy = rect.midY
        bolt.move(to: NSPoint(x: cx + 4.5, y: cy + 6))
        bolt.line(to: NSPoint(x: cx - 5.0, y: cy + 0.3))
        bolt.line(to: NSPoint(x: cx - 0.6, y: cy + 0.3))
        bolt.line(to: NSPoint(x: cx - 3.6, y: cy - 6))
        bolt.line(to: NSPoint(x: cx + 5.4, y: cy + 1.2))
        bolt.line(to: NSPoint(x: cx + 0.9, y: cy + 1.2))
        bolt.line(to: NSPoint(x: cx + 4.5, y: cy + 6))
        bolt.close()
        NSColor.white.setFill()
        bolt.fill()
    }
}

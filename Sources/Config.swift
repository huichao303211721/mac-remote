import Foundation

// 一个遥控器按键映射到 Mac 上的动作
enum RemoteAction: String, Codable, CaseIterable {
    case none
    case leftClick
    case rightClick
    case returnKey
    case escapeKey
    case spaceKey
    case deleteKey
    case fnHold          // 按住当 Fn（给豆包输入法长按说话用）
    case volumeUp
    case volumeDown
    case mute
    case playPause
    case nextTrack
    case previousTrack
    case lockScreen
    case appSwitcher
    case customKey

    var title: String {
        switch self {
        case .none: return "不启用"
        case .leftClick: return "鼠标左键"
        case .rightClick: return "鼠标右键"
        case .returnKey: return "回车"
        case .escapeKey: return "Esc"
        case .spaceKey: return "空格"
        case .deleteKey: return "删除"
        case .fnHold: return "Fn（按住说话）"
        case .volumeUp: return "音量加"
        case .volumeDown: return "音量减"
        case .mute: return "静音开关"
        case .playPause: return "播放 / 暂停"
        case .nextTrack: return "下一首"
        case .previousTrack: return "上一首"
        case .lockScreen: return "锁屏"
        case .appSwitcher: return "切换 App（⌘Tab）"
        case .customKey: return "自定义按键"
        }
    }
}

// 遥控器上可以点选的“逻辑按键”。code 是 HID 报告 0xFB 的第二个字节。
struct RemoteButton: Codable, Hashable {
    var id: String          // siri / tv / back / play / volumeUp / volumeDown / mute / power / center
    var code: UInt16?        // 已知的 HID 编码；未知时为 nil，等待“学习”
    var action: RemoteAction
    var keyCode: UInt16?    // customKey 用
    var command: Bool = false
    var option: Bool = false
    var control: Bool = false
    var shift: Bool = false
    var repeatWhileHeld: Bool = false
    var enabled: Bool = true

    var title: String {
        switch id {
        case "siri": return "Siri 键"
        case "tv": return "TV / Home"
        case "back": return "返回"
        case "play": return "播放 / 暂停"
        case "volumeUp": return "音量 +"
        case "volumeDown": return "音量 −"
        case "mute": return "静音"
        case "power": return "电源"
        case "center": return "触控板中心"
        default: return id
        }
    }
}

struct PadSettings: Codable {
    var enabled = true
    var pointerSpeed: Double = 1.0
    var tapToClick = true
    var twoFingerScroll = true
}

struct AppConfig: Codable {
    var buttons: [RemoteButton]
    var pad = PadSettings()
    var launchAtLogin = false
    var showDockIcon = true
    var controlEnabled = true

    static func makeDefault() -> AppConfig {
        AppConfig(buttons: [
            RemoteButton(id: "siri", code: 0x20, action: .fnHold),
            RemoteButton(id: "tv", code: nil, action: .returnKey),
            RemoteButton(id: "back", code: nil, action: .escapeKey),
            RemoteButton(id: "play", code: nil, action: .playPause),
            RemoteButton(id: "volumeUp", code: 0x02, action: .volumeUp, repeatWhileHeld: true),
            RemoteButton(id: "volumeDown", code: 0x04, action: .volumeDown, repeatWhileHeld: true),
            RemoteButton(id: "mute", code: nil, action: .mute),
            RemoteButton(id: "power", code: nil, action: .lockScreen),
            RemoteButton(id: "center", code: 0x08, action: .leftClick),
        ])
    }
}

final class Store {
    static let shared = Store()
    private let url: URL
    var config: AppConfig

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RemotePad", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("config.json")
        if let data = try? Data(contentsOf: url),
           let c = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = c
        } else {
            config = AppConfig.makeDefault()
            save()
        }
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(config) {
            try? data.write(to: url)
        }
        NotificationCenter.default.post(name: .configChanged, object: nil)
    }

    func button(id: String) -> RemoteButton? { config.buttons.first { $0.id == id } }

    func update(_ b: RemoteButton) {
        if let i = config.buttons.firstIndex(where: { $0.id == b.id }) {
            config.buttons[i] = b
            save()
        }
    }

    // 通过 HID 编码找逻辑按键
    func button(code: UInt16) -> RemoteButton? { config.buttons.first { $0.code == code } }
}

extension Notification.Name {
    static let configChanged = Notification.Name("RemotePad.configChanged")
    static let remoteStateChanged = Notification.Name("RemotePad.remoteStateChanged")
}

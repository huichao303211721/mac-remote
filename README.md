# Mac 遥控（RemotePad）

把 **Apple TV 4K 的 Siri Remote（第三代，USB‑C 版）** 当作 Mac 的外设使用：触控盘当鼠标，音量键控系统音量，Siri 键唤起语音输入，播放/静音/电源键也能映射成任意快捷键。

纯原生 Swift + SceneKit + IOKit + MultitouchSupport 实现，无第三方依赖，不需要内核扩展。

> Apple TV Remote / Siri Remote 是 Apple 的产品。本项目与 Apple 无关联，仅为个人使用而做的第三方工具。

---

## 获取方式

- **源码**：本仓库免费，MIT 许可，自行编译即可（见下方「编译」）。
- **现成 App**：¥1（含打包好的通用二进制、首次打开助手与安装说明）。购买入口见仓库右侧 Releases 或商品页；源码用户无需购买。

> 仓库不分发 Apple 的 3D 模型资源，现成 App 使用自绘简化外观，功能与完整版一致。

## 功能

| 区域 | 默认行为 | 可改 |
| --- | --- | --- |
| 触控盘 | 鼠标移动；轻点 = 左键单击；双指滑动 = 滚动 | 指针速度、点按、双指 |
| `+ / −` | 系统音量加 / 减（按住连续触发） | ✅ |
| 静音键 | 系统静音（可自定义为任意快捷键） | ✅ |
| `Siri` 键 | 触发语音输入（默认等效按住 `fn`，可配豆包输入法等） | ✅ |
| `TV / Home` | 切换 App（⌘Tab） | ✅ |
| 返回键 | `Esc` | ✅ |
| 播放/暂停 | 媒体播放暂停 | ✅ |
| 电源键 | 锁屏 | ✅ |

其它：

- **遥控器电量显示**：通过 BLE Battery Service 读取真实电量，插线充电时显示绿色电池 + 闪电 +「充电中」。
- **可旋转 3D 遥控器示意图**：点击模型上的按键即可编辑该键的映射。
- **按键学习模式**：不用查表，按下遥控器上的物理键让 App 自己识别。
- 配置本地保存：`~/Library/Application Support/RemotePad/config.json`
- 日志：`~/Library/Logs/RemotePad.log`

## 系统要求

- macOS 13 或更新（Apple Silicon / Intel 均可，`ARCHS=universal` 可编通用二进制）
- 已与 Mac 蓝牙配对的 Apple TV Remote（第 2/3 代均可，实测第三代 USB‑C 版）
- 第一次运行需授予 **辅助功能** 与 **蓝牙** 权限

## 编译

```bash
# 只编当前架构（Apple Silicon）
./build.sh

# 编通用二进制（Intel + Apple Silicon）
ARCHS=universal ./build.sh

# 用你自己的签名身份
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
```

产物：`build/RemotePad.app`，可直接拖进「应用程序」运行。

脚本默认使用 ad‑hoc 签名（`-`）。ad‑hoc 签名每次重编都会被视为新程序，**辅助功能权限需要重新授予**；如果你想长期自用，建议自己生成一张本地代码签名证书（钥匙串 → 证书助理 → 创建证书，类型选「代码签名」），然后：

```bash
CODESIGN_IDENTITY="你的证书名" ./build.sh
```

## 首次使用

1. 在「系统设置 → 蓝牙」把遥控器与 Mac 配对。
2. 把 `build/RemotePad.app` 拖到 `/Applications` 并打开。
3. 到「系统设置 → 隐私与安全性 → 辅助功能」勾选 **Mac 遥控**（不勾选时按键/指针不会生效，日志里会出现 `launch AX=false`）。
4. 首次读电量会弹一次蓝牙授权，点「允许」。
5. 打开 App → 「映射」页 → 点遥控器示意图上的按键 → 在右侧下拉框选择动作；不确定键码时用「学习遥控器按键」。

> 若 App 在 IDE/终端下启动时拿不到辅助功能权限，从 **Finder** 双击启动即可（签名身份与启动上下文会影响 TCC 授权）。

## 工作原理（给想改代码的人）

```
Sources/
  main.swift          App 入口、菜单栏状态项、启动流程
  MainWindow.swift     主窗口与各页面（映射 / 场景 / 快捷指令 / 设备设置 / 语音 / 更新）
  UIComponents.swift   3D 遥控器视图（SceneKit）、电量电池图形、通用控件
  HID.swift            IOKit HID 读取遥控器按键（report ID 0xFB）
  Touch.swift          MultitouchSupport 读取触控盘（不依赖辅助功能权限）
  Synth.swift          合成鼠标/键盘/媒体事件
  AudioVolume.swift    系统音量与静音
  Battery.swift        CoreBluetooth 读取电量与充电状态
  Config.swift         配置模型与持久化
  Log.swift            日志
Resources/SiriRemote.usdz   （可选）官方外观 3D 模型
```

- **按键**：`IOHIDManager` 匹配 Apple 的 vendor `0x004C`，从 HID report 里取 `code = (report[1] << 8) | report[2]` 作为按键标识。
- **触控**：`MultitouchSupport.framework` 的私有 API，读取 `MTDevice` 的触点流，转成指针位移与手势。
- **电量/充电**：`CoreBluetooth.retrieveConnectedPeripherals(withServices:)` 拿到已连接的遥控器，读 `0x180F` 服务的 `0x2A19`（电量百分比）与 `0x2A1A`（供电状态位，`wired == 2` 即判为充电中），读完立即断开这条多余连接。

## 已知限制

- 官方 USDZ 模型是单网格，**点选按键时模型本身不做高亮**，只有右侧卡片切换（不影响使用）。
- 遥控器只在「已配对且已连接」时可用；系统蓝牙断连后需要重新连接。
- 与其它会抓取 HID 的遥控器工具（如 Voxa、Remote Buddy）**不能同时运行**，否则按键会被抢走。
- 触控使用私有框架 `MultitouchSupport`，未来 macOS 版本若改动接口可能失效。
- 仓库**不包含** Apple 的 3D 模型资源（见下）。

## 版权与资源说明

`Resources/SiriRemote.usdz` 是从官方 App 中提取的 3D 模型，**版权归 Apple 所有，不随本仓库分发**（已在 `.gitignore` 中排除）。缺少该文件时程序会自动使用自绘的程序化模型，功能不受影响。请勿把该文件提交到公开仓库或打包进对外发布的安装包。

## 许可证

MIT，见 [LICENSE](LICENSE)。

## 参与

Issue / PR 都欢迎。改代码前建议先读 `Sources/HID.swift` 与 `Sources/Touch.swift`，这两处涉及硬件输入，最容易踩坑。

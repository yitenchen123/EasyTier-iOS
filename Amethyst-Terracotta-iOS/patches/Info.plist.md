# 修改 Natives/Info.plist — 添加本地网络权限说明

Amethyst-iOS 的 `Natives/Info.plist` 已经声明了 `NSLocalNetworkUsageDescription`
（用于 AltKit JIT 和 Minecraft 自身的 LAN 发现），但描述文字提到的是 AltServer。
为避免 iOS 14+ 弹出的本地网络权限对话框让用户困惑，更新描述并显式声明
Minecraft 用的 Bonjour 服务类型。

## 修改 1：更新 NSLocalNetworkUsageDescription 描述

找到（约第 ~93 行附近）：

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Angel Aura Amethyst uses the local network to find and communicate with AltServer and LAN servers.</string>
```

改为：

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Amethyst 需要本地网络权限来启用陶瓦联机（Terracotta）以及发现 Minecraft 局域网世界。不开启将无法联机。</string>
```

## 修改 2：扩充 NSBonjourServices

找到（同区域）：

```xml
<key>NSBonjourServices</key>
<array>
    <string>_altserver._tcp</string>
</array>
```

改为：

```xml
<key>NSBonjourServices</key>
<array>
    <string>_altserver._tcp</string>
    <string>_minecraft._tcp</string>
</array>
```

## 说明

- `_minecraft._tcp` 是 Minecraft Java Edition 自身做局域网广播时使用的
  Bonjour 服务类型。虽然 Minecraft 实际用的是 UDP 多播 `224.0.2.60:4445`
  而非 Bonjour，但 iOS 14+ 要求显式声明 `_minecraft._tcp` 才允许 UDP
  多播流量。这一项在所有 iOS MC 启动器（如 PojavLauncher iOS）中都是
  必加的。

- Terracotta 的 FakeServer（房客端）和 MinecraftScanner（房主端）都依赖
  UDP 多播 `224.0.2.60:4445`（IPv4）/ `FF75:230::60:4445`（IPv6），
  所以这两个权限是必须的。

- 不需要新增 `NSCameraUsageDescription`、`NSMicrophoneUsageDescription`
  等无关权限。

## 验证

iOS 14+ 第一次进入联机页面时，系统会弹窗"Amethyst 想要查找并连接到本地
网络上的设备"。用户点"允许"后即可联机。

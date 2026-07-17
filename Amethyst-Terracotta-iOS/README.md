# Amethyst-Terracotta-iOS

为 [Amethyst-iOS](https://github.com/AngelAuraMC/Amethyst-iOS)（及
[MyRemastered 改版](https://github.com/herbrine8403/Amethyst-iOS-MyRemastered)）
添加"陶瓦联机"（Terracotta / EasyTier）功能，使 iOS 上的 Minecraft Java
Edition 能与 [HMCL](https://github.com/HMCL-dev/HMCL)、
[FCL](https://github.com/FCL-Team/FoldCraftLauncher)、
[ZalithLauncher2](https://github.com/ZalithLauncher/ZalithLauncher2) 互相联机。

## 协议互通保证

**100% 与 HMCL/FCL/ZL2 协议一致**，因为：

- iOS 端的 `libterracotta.a` 是 [`burningtnt/Terracotta`](https://github.com/burningtnt/Terracotta) 原版 Rust 源码加一个 `lib_ios.rs`（C ABI 入口）编译的
- 房间码算法、EasyTier 配置、Scaffolding 协议、FakeServer、MinecraftScanner 全部复用同一份 Rust 代码
- 不重写任何协议逻辑，只把 Android 的 JNI 接口替换为 iOS 的 C ABI
- 详见 [docs/PROTOCOL.md](docs/PROTOCOL.md)

## 架构

```
┌──────────────────────────────────────────────────────┐
│ Amethyst-iOS (Objective-C, UIKit)                    │
│  ┌────────────────────────────────────────────────┐  │
│  │ LauncherTerracottaViewController               │  │
│  │   联机 UI（创建/加入房间、玩家列表）            │  │
│  │   每 500ms 轮询状态                             │  │
│  └──────────────┬─────────────────────────────────┘  │
│                 │ Obj-C → C ABI                       │
│  ┌──────────────▼─────────────────────────────────┐  │
│  │ TerracottaBridge  (Obj-C 包装层)               │  │
│  │   terracotta_ios_start / get_state / ...       │  │
│  └──────────────┬─────────────────────────────────┘  │
└─────────────────┼────────────────────────────────────┘
                  │ C ABI (extern "C")
┌─────────────────┼────────────────────────────────────┐
│ libterracotta.a (Rust, aarch64-apple-ios)           │
│  ┌──────────────▼─────────────────────────────────┐  │
│  │ lib_ios.rs  (C ABI 入口，本项目新增)            │  │
│  └──────────────┬─────────────────────────────────┘  │
│  ┌──────────────▼─────────────────────────────────┐  │
│  │ burningtnt/Terracotta 原版代码（未修改）        │  │
│  │  - controller (状态机, room 码)                 │  │
│  │  - scaffolding (TCP 13448 协议)                 │  │
│  │  - mc (FakeServer + MCScanner, UDP 多播)        │  │
│  │  - easytier (linkage_impl, no_tun+port_forward) │  │
│  └──────────────┬─────────────────────────────────┘  │
│  ┌──────────────▼─────────────────────────────────┐  │
│  │ burningtnt/EasyTier fork (v2.5.0-terracotta.2) │  │
│  │  虚拟网络层, P2P, KCP, 加密                     │  │
│  └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
                  │
                  ▼ EasyTier 隧道
         HMCL / FCL / ZalithLauncher2
```

## 文件结构

```
Amethyst-Terracotta-iOS/
├── README.md                          本文件
├── docs/
│   └── PROTOCOL.md                    协议解析文档（必读）
├── rust/                              Rust 端（fork Terracotta + iOS 支持）
│   ├── INSTRUCTIONS.md                如何修改 Terracotta 仓库
│   └── src/
│       └── lib_ios.rs                 iOS C ABI 入口（新增到 Terracotta fork）
├── Natives/terracotta/                Obj-C 模块（集成进 Amethyst-iOS）
│   ├── terracotta.h                   C ABI 头文件
│   ├── TerracottaLog.h/.m             日志
│   ├── TerracottaBridge.h/.m          Obj-C 桥接层
│   └── ui/
│       └── LauncherTerracottaViewController.h/.m   联机 UI
├── scripts/
│   └── build_ios.sh                   macOS 上编译 libterracotta.xcframework
└── patches/                           Amethyst-iOS 集成修改说明
    ├── CMakeLists.txt.md              修改 CMake
    ├── Info.plist.md                  修改 Info.plist
    ├── LauncherMenuViewController.md  在侧边菜单加入口
    └── entitlements.md                权限说明
```

## 构建步骤

> **必须在 macOS 上执行**（Linux/Windows 无法编译 iOS）。需要 Xcode 15+、
> iOS 17.5 SDK、Rust nightly。

### 1. 克隆并 patch Terracotta 仓库

```bash
# 克隆 Terracotta
git clone https://github.com/burningtnt/Terracotta.git
cd Terracotta

# 按 rust/INSTRUCTIONS.md 修改以下文件：
#   - src/lib.rs          (添加 #[cfg(target_os = "ios")] 分支)
#   - src/easytier/mod.rs (让 iOS 用 linkage_impl)
#   - Cargo.toml          (添加 iOS 依赖)
# 然后把本项目的 rust/src/lib_ios.rs 复制到 Terracotta/src/lib_ios.rs
cp /path/to/Amethyst-Terracotta-iOS/rust/src/lib_ios.rs src/lib_ios.rs
```

### 2. 编译 libterracotta.xcframework

```bash
cd /path/to/Amethyst-Terracotta-iOS
chmod +x scripts/build_ios.sh
./scripts/build_ios.sh
# 产出: build/ios/libterracotta.xcframework
```

### 3. 集成到 Amethyst-iOS

```bash
# 克隆 Amethyst-iOS（官方或改版均可）
git clone https://github.com/AngelAuraMC/Amethyst-iOS.git
cd Amethyst-iOS

# 复制 Obj-C 模块
cp -r /path/to/Amethyst-Terracotta-iOS/Natives/terracotta Natives/terracotta

# 按 patches/ 下的说明修改：
#   - Natives/CMakeLists.txt     (见 patches/CMakeLists.txt.md)
#   - Natives/Info.plist         (见 patches/Info.plist.md)
#   - Natives/LauncherMenuViewController.m  (见 patches/LauncherMenuViewController.md)
#   - entitlements 不用改        (见 patches/entitlements.md)

# 把 xcframework 放到 Amethyst-iOS/build/ios/
mkdir -p build/ios
cp -r /path/to/Amethyst-Terracotta-iOS/build/ios/libterracotta.xcframework build/ios/

# 构建
make dsym package
```

### 4. 安装

产出的 IPA 用 TrollStore / AltStore / SideStore 安装。

## 使用说明

1. 在 Amethyst 中打开侧边菜单 → "陶瓦联机"
2. 首次使用会弹出协议确认对话框，点"同意并继续"
3. **房主**：
   - 先在 Minecraft 中按 ESC → "对局域网开放"
   - 回到 Amethyst 联机页面，点"创建房间"
   - 等待状态变为"房间已创建"
   - 把邀请码（`U/XXXX-XXXX-XXXX-XXXX`）分享给好友（自动复制到剪贴板）
4. **房客**：
   - 点"加入房间"
   - 输入好友分享的邀请码
   - 等待状态变为"已加入房间"
   - 在 Minecraft 多人游戏界面会自动看到"陶瓦联机大厅"，双击连接即可

## 关键技术决策

| 决策 | 理由 |
|---|---|
| 复用 Terracotta 原版 Rust 代码 | 协议 100% 与 HMCL/FCL/ZL2 一致 |
| iOS 用 `linkage_impl`（库链接） | iOS 沙盒禁止 spawn 子进程 |
| iOS 用 `no_tun = true` + port_forward | 避免 NEPacketTunnelProvider 需要 Apple 付费权限 |
| iOS 不调用 VpnService | 无 VPN，`on_vpnservice_change` 是 no-op |
| C ABI 而非 JNI | iOS 无 JNI，Obj-C 通过 C ABI 调用 Rust |
| Obj-C 而非 Swift | Amethyst-iOS 是纯 Obj-C 项目，保持一致 |

## 限制与已知问题

1. **无法在 Linux/Windows 上构建**：iOS 编译需要 macOS + Xcode。
2. **EasyTier fork 可能需要 iOS 兼容补丁**：`burningtnt/EasyTier` fork
   主要针对 Android，可能有个别代码缺少 iOS cfg 分支。如果编译失败，
   参照 `scripts/build_ios.sh` 末尾的 TROUBLESHOOTING 部分，给 EasyTier
   fork 打 iOS 补丁（上游 `EasyTier/EasyTier` 已有 iOS 支持，可参考）。
3. **公共节点可用性**：4 个硬编码公共节点（`public.easytier.top` 等）
   由 EasyTier 社区维护，不保证 100% 在线。如果连不上，所有端（包括
   HMCL/FCL/ZL2）都会失败，不是 iOS 端的问题。
4. **NAT 穿透**：对称 NAT（Symmetric NAT）环境下可能无法 P2P，会回退
   到 KCP 代理。极少数严格 NAT 环境下可能完全连不上，这是 EasyTier 的
   通用限制，所有端都一样。
5. **iOS 后台限制**：App 进入后台后，EasyTier 的 TCP/UDP socket 会被
   系统挂起。联机时请保持 Amethyst 在前台，或开启屏幕常亮。
6. **MC 客户端必须在前台**：Amethyst 的 JVM 在后台也会被挂起，所以
   联机时 MC 必须保持运行。

## 调试

- 日志路径：`<POJAV_HOME>/terracotta.log`（通常是 Documents/terracotta/）
- Xcode 控制台会显示 `[Terracotta-iOS]` 前缀的日志
- Console.app 中按 subsystem `org.angelauramc.amethyst`、category
  `Terracotta` 过滤
- 状态 JSON 可通过 `terracotta_ios_get_state()` 获取（见
  `TerracottaBridge.pollState`）

## 许可证

本项目的 Obj-C 代码（`Natives/terracotta/`）随 Amethyst-iOS 主项目
许可证发布。

Rust 端（`rust/src/lib_ios.rs`）随 `burningtnt/Terracotta` 许可证发布。
Terracotta 和 EasyTier 都是开源软件，详见各自仓库。

## 致谢

- [Burning_TNT](https://github.com/burningtnt) — Terracotta 作者，整个
  陶瓦联机协议的设计者和实现者
- [EasyTier](https://github.com/EasyTier/EasyTier) — 虚拟网络层
- [HMCL](https://github.com/HMCL-dev/HMCL) / [FCL](https://github.com/FCL-Team/FoldCraftLauncher) /
  [ZalithLauncher2](https://github.com/ZalithLauncher/ZalithLauncher2) —
  协议参考实现
- [Amethyst-iOS](https://github.com/AngelAuraMC/Amethyst-iOS) — iOS
  Minecraft Java 启动器（基于 PojavLauncher）

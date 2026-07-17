# 修改 entitlements — 权限说明

## 当前状态

Amethyst-iOS 三份 entitlements（`entitlements.trollstore.xml`、
`entitlements.sideload.xml`、`entitlements.codesign.xml`）**都不包含**
NetworkExtension 相关权限。

## 当前方案：无需修改权限

当前 Terracotta iOS 集成方案使用 EasyTier 的 `no_tun = true` + 端口转发
模式，**完全不需要** NetworkExtension / NEPacketTunnelProvider / packet-tunnel-provider
权限。三份 entitlements 保持原样即可。

工作原理：
- EasyTier 不创建系统级 TUN 设备
- 房客的 Minecraft 客户端连接 `127.0.0.1:<本地端口>`
- EasyTier 在用户态把 `127.0.0.1:<本地端口>` 端口转发到房主的虚拟 IP
  `10.144.144.1:<MC端口>`（通过 EasyTier 的虚拟网络层，不走系统 VPN）
- 整个过程只用到普通 socket 权限，任何签名方式都能用

这与 HMCL/FCL/ZalithLauncher2 在 Android 上的实现完全一致——它们也是
`no_tun = true` + port_forward，Android 端的 VpnService 仅用于创建 TUN
fd 给 EasyTier 写包，但在 no_tun 模式下连这个都不需要。

## 替代方案（不推荐）：使用 NEPacketTunnelProvider

如果你将来想改成"系统级 VPN"模式（让所有 App 流量都走 EasyTier），
需要在三份 entitlements 中添加：

```xml
<key>com.apple.developer.networking.networkextension</key>
<array>
    <string>packet-tunnel-provider</string>
</array>
```

并在 `Natives/CMakeLists.txt` 中链接 `-framework NetworkExtension`。

但此方案：
1. **需要 Apple 付费开发者账号**（$99/年），免费侧载和 TrollStore 无法使用
2. 需要 Apple 审核批准 NetworkExtension 权限
3. 与 HMCL/FCL/ZL2 的实现不同（它们都没用系统 VPN 模式）

所以**强烈建议保持当前 no_tun 方案**。

## 关于 com.apple.private.security.no-sandbox

Amethyst-iOS 的 TrollStore entitlements 已包含
`com.apple.private.security.no-sandbox`，这意味着 Terracotta 可以：
- 绑定任意本地端口（包括 13448 scaffolding 端口）
- 创建 UDP 多播 socket（224.0.2.60:4445）用于 FakeServer 和 MCScanner
- 读写 POJAV_HOME 下的文件（machine-id、日志）

如果用 AltStore/SideStore 侧载（无 no-sandbox），上述操作仍在 App 沙盒
允许范围内（bind 本地端口、UDP 多播、Documents 目录读写都是允许的），
所以两种安装方式都能工作。

## 验证

构建并用 TrollStore 或 AltStore 安装后：
1. 进入"陶瓦联机"页面
2. 创建房间 → 应能看到邀请码（U/XXXX-XXXX-XXXX-XXXX）
3. 在另一台设备上用 HMCL/FCL/ZL2 加入该邀请码 → 应能互相联机

如果绑定端口失败，检查 App 是否有 `no-sandbox` 权限（TrollStore 有，
AltStore 没有，但 AltStore 也能 bind 普通端口）。

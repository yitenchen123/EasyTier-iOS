# 修改 Natives/LauncherMenuViewController.m — 在侧边菜单加入"陶瓦联机"

Amethyst-iOS 的侧边菜单在 `Natives/LauncherMenuViewController.m` 的
`viewDidLoad` 中通过 `self.options` 数组定义。当前结构是：

```objc
self.options = @[
    [LauncherMenuCustomItem vcClass:LauncherNewsViewController.class],
    [LauncherMenuCustomItem vcClass:LauncherProfilesViewController.class],
    [LauncherMenuCustomItem vcClass:LauncherPreferencesViewController.class],
].mutableCopy;
// 后面追加: Custom Controls / Execute JAR / Send Logs (action 形式)
```

## 修改 1：在 options 数组中插入"陶瓦联机"项

把 `self.options` 的初始化改成（在 `LauncherProfilesViewController` 之后、
`LauncherPreferencesViewController` 之前插入一项）：

```objc
#import "LauncherTerracottaViewController.h"  // 文件顶部

// ... viewDidLoad 中 ...
self.options = @[
    [LauncherMenuCustomItem vcClass:LauncherNewsViewController.class],
    [LauncherMenuCustomItem vcClass:LauncherProfilesViewController.class],
    [LauncherMenuCustomItem vcClass:LauncherTerracottaViewController.class],  // 新增
    [LauncherMenuCustomItem vcClass:LauncherPreferencesViewController.class],
].mutableCopy;
```

## 修改 2（可选）：设置菜单图标

如果 `LauncherMenuCustomItem` 支持 `imageName:`（看 Amethyst-iOS 实际
API；Remastered 版可能有），可以加图标：

```objc
// 创建带图标的菜单项
LauncherMenuCustomItem *terracottaItem =
    [LauncherMenuCustomItem vcClass:LauncherTerracottaViewController.class];
terracottaItem.imageName = @"MenuTerracotta";  // 需要 Assets.xcassets 资源
```

如果不想加图标，直接用第一段代码即可——SF Symbols 会在运行时显示默认图标。

## 修改 3（推荐）：传递当前玩家名

在创建 `LauncherTerracottaViewController` 之前，从 Amethyst 的账号管理
器获取当前登录的 Microsoft 账号名，设置给 `playerName`。

由于 `LauncherMenuCustomItem` 用 `vcClass:` 创建实例（由菜单框架统一
实例化），你可能需要在 `LauncherTerracottaViewController.viewDidLoad` 中
自己读取当前账号名。在 `LauncherTerracottaViewController.m` 的
`viewDidLoad` 里加：

```objc
// 读取当前 Amethyst 账号名（具体 API 看 Amethyst 的 authenticator 模块）
// 例如：
// id currentAccount = [AmethystAccountManager currentAccount];
// self.playerName = currentAccount.username ?: @"Amethyst Player";
```

具体的账号读取 API 需要查看 `Natives/authenticator/` 目录的实现。
最简单的做法是让玩家在联机页面手动输入昵称——加一个 UITextField。

## 修改 4（可选）：本地化

在 `Natives/resources/en.lproj/Localizable.strings` 和
`Natives/resources/zh-Hans.lproj/Localizable.strings` 中添加：

```
"Terracotta.Title" = "Terracotta Multiplayer";
"Terracotta.Waiting" = "Waiting to start";
"Terracotta.HostScanning" = "Waiting for you to open a LAN world in Minecraft…";
"Terracotta.HostOk" = "Room created. Share the invite code with your friends.";
"Terracotta.GuestOk" = "Joined. Connect in Minecraft multiplayer screen.";
```

中文版：
```
"Terracotta.Title" = "陶瓦联机";
"Terracotta.Waiting" = "等待开始联机";
"Terracotta.HostScanning" = "正在等待你在 Minecraft 中开放局域网世界…";
"Terracotta.HostOk" = "房间已创建，分享邀请码给好友吧";
"Terracotta.GuestOk" = "已加入房间，可以连接服务器了";
```

## 验证

构建并安装 App 后，侧边菜单应该出现"陶瓦联机"项，点击进入联机页面。

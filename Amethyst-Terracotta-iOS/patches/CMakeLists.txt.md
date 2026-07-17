# 修改 Natives/CMakeLists.txt — 接入 Terracotta 模块

在 Amethyst-iOS 的 `Natives/CMakeLists.txt` 中做以下修改。

## 1. 添加 Terracotta 源文件

在 `add_executable(AngelAuraAmethyst ...)` 的源文件列表末尾追加：

```cmake
# Terracotta (陶瓦联机) module
terracotta/TerracottaLog.m
terracotta/TerracottaBridge.m
terracotta/ui/LauncherTerracottaViewController.m
```

## 2. 添加头文件搜索路径

在现有的 `include_directories(...)` 块中追加（约第 15-30 行）：

```cmake
${CMAKE_CURRENT_SOURCE_DIR}/terracotta
${CMAKE_CURRENT_SOURCE_DIR}/terracotta/ui
```

## 3. 链接 libterracotta.xcframework

在 `target_link_libraries(...)` 块末尾追加（约第 184-205 行）：

```cmake
# Terracotta static library (Rust build). The xcframework is expected at
# ${PROJECT_ROOT}/build/ios/libterracotta.xcframework (see scripts/build_ios.sh).
# CMake doesn't natively consume xcframeworks, so we link the .a directly
# and add its include path.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../build/ios/libterracotta.xcframework")
    # Find the device slice (aarch64-apple-ios)
    file(GLOB TERRACOTTA_A
        "${CMAKE_CURRENT_SOURCE_DIR}/../build/ios/libterracotta.xcframework/ios-arm64/libterracotta.a")
    target_link_libraries(AngelAuraAmethyst ${TERRACOTTA_A})
    target_include_directories(AngelAuraAmethyst PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/terracotta")
endif()
```

## 4. 链接额外 framework

iOS 上 Terracotta 需要 `os/log`（已在 Foundation 中），无需额外 framework。
但如果 EasyTier 的 iOS 编译需要 `NetworkExtension.framework`（如果你将来
改用 NEPacketTunnelProvider 方案），在 `target_link_libraries` 中追加：

```cmake
# Only needed if you switch from no_tun+port_forward to NEPacketTunnelProvider:
# -framework NetworkExtension
```

当前方案（no_tun + port_forward）**不需要** NetworkExtension。

## 5. 修改 Makefile（顶层）

Amethyst-iOS 顶层 `Makefile` 会调用 CMake。无需修改 Makefile 本身，但如果你
想让 `make` 自动先编译 Rust 库，可以在 `Makefile` 顶部加一个依赖：

```makefile
# Optional: auto-build Rust static lib before building the app
# Comment out if you build the .xcframework manually.
terracotta-lib:
	cd scripts && ./build_ios.sh

# Add terracotta-lib as a prerequisite of the main build target
# (Find the main build target, e.g. `build:` and add `: terracotta-lib`)
```

## 验证

修改完成后，在 macOS 上：

```bash
cd Amethyst-iOS
make dsym package
```

如果链接成功，`AngelAuraAmethyst.app` 中会包含 `libterracotta.a` 的符号。
用 `nm` 验证：

```bash
nm -gU build/AngelAuraAmethyst.app/AngelAuraAmethyst | grep terracotta_ios
```

应看到：
```
_terracotta_ios_start
_terracotta_ios_get_state
_terracotta_ios_set_waiting
_terracotta_ios_set_scanning
_terracotta_ios_set_guesting
_terracotta_ios_verify_room_code
_terracotta_ios_get_metadata
_terracotta_ios_free_string
```

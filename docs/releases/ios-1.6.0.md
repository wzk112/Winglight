# Winglight for iPad and iPhone 1.6.0

原生 iOS/iPadOS 18+ 版本，优先适配 iPad，并支持 iPhone、横竖屏和窄窗口。
与电脑版共用完整场景逻辑、Metal 渲染和原始资源：9 种机型、17 套模型装配、
309 个机型／涂装组合，以及全部灯光、天气、日照、气流、飞行动效和画质选项。

- iPad 宽窗口显示侧栏；iPhone、竖屏和窄窗口使用控制面板。
- 拖动旋转、捏合缩放、双击复位，支持七种视角及沉浸模式。
- 30 / 60 / 最高 120 帧和高精度模式，HDR/EDR 依据设备与系统实际余量工作。
- 全部资源内置，运行时无需下载、登录或联网。

下载 `Winglight-1.6.0-iOS-unsigned.ipa`，使用自己的账号签名后安装。
**此 IPA 未签名，不能直接安装，也不是 App Store / TestFlight 包。**
免费账号的有效期及设备应用数量限制由 Apple 决定。

源码、构建、功能对应和安装说明见 [iOS 文档](https://github.com/wzk112/Winglight/blob/ios-v1.6.0/docs/IOS.md)，
实际检查记录见 [iOS 验证记录](https://github.com/wzk112/Winglight/blob/ios-v1.6.0/docs/IOS_VALIDATION.md)。
应用代码采用 GPL-2.0-only；第三方模型与涂装保留原许可，包内附署名和许可证。

对应源码为 `ios-v1.6.0` 标签，完整重建还需要文档指定、带哈希校验的
1.5.2 资源包。GitHub 自动生成的源码 ZIP
不含二进制大文件；下载 IPA 则已包含全部运行资源。

本次连接的 iPad 和 iPhone 均因免费开发账号的三个应用名额已满而未能安装，
未删除现有应用。因此真机 HDR 峰值、持续帧率、功耗与定位仍须实机检查。
此版本不会替换既有 macOS 1.5.2 下载。

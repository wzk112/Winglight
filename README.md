# Winglight

原生 macOS 三维飞机灯光模拟器，以 SwiftUI / AppKit 和 Metal 构建。支持九种机型、17 套模型装配和 **309 个机型／涂装组合**，可观察外部灯光、几何遮挡、日照、天气和飞行动效。

Native macOS aircraft-light visualizer built with SwiftUI, AppKit, and Metal.
GPL v2; bundled artwork retains its upstream license and attribution.

## 下载 1.5.1

[发布页与更新说明](https://github.com/wzk112/Winglight/releases/tag/v1.5.1) ·
[macOS Apple Silicon 完整应用 ZIP](https://github.com/wzk112/Winglight/releases/download/v1.5.1/Winglight-1.5.1-macOS-arm64.zip) ·
[SHA-256 校验文件](https://github.com/wzk112/Winglight/releases/download/v1.5.1/SHA256SUMS.txt)

需要 **macOS 15+ 和 Apple Silicon**。解压后将 `Winglight.app` 拖到「应用程序」。
应用已内置全部运行资源，直接运行无需另下资源包。
此版本使用 Apple Development 签名，**未做 Developer ID 公证**；macOS
可能要求在「系统设置 → 隐私与安全性」确认允许打开。也可按下文从源码构建。

1.5.1 在保留分辨率、MSAA、模型、粒子数量和 HDR 上限的前提下减少重复渲染；
开发机六个代表场景的 GPU 时间降低约 4.0–10.4%，不等同于各设备的帧率或续航增幅。
闪电更新为细折线主通道、不规则分支、局部云层照明及多次回击。
详见 [更新记录](CHANGELOG.md) 和 [性能与画面对比](docs/PERFORMANCE.md)。

## 从源码运行

需要 macOS 15+、Xcode（Swift 6 与 Apple Metal Toolchain）及 Python 3。
macOS 26+ 使用原生 Liquid Glass，较早系统使用材质回退。

```sh
git clone https://github.com/wzk112/Winglight.git
cd Winglight
git checkout v1.5.1
python3 scripts/assets.py fetch
./scripts/build.sh
open dist/Winglight.app
```

模型和贴图以约 1.1 GB 的 [1.5.0 资源包](https://github.com/wzk112/Winglight/releases/download/v1.5.0/Winglight-1.5.0-assets.tar.gz)单独提供；解压后约 2.6 GB。
**1.5.1 未改变这些资源，继续使用同一份不可变资源包**；下载脚本已指定其版本和哈希。
下载脚本仅使用 Python 标准库，校验压缩包及全部 504 个文件的 SHA-256。
资源准备完成后，构建和运行无需联网；常规构建无需安装 Python 第三方包。
GitHub 自动源码 ZIP 不含大文件，仍须运行下载命令。

默认输出 `dist/Winglight.app`，采用临时签名。`BUILD_DIR`、`APP_PATH` 和
`SIGNING_IDENTITY` 可设置本地输出及签名，不需要提交证书或账号凭据。
GitHub 同时提供完整应用 ZIP；当前没有已公证的安装程序。

## 使用

- 拖动旋转，滚轮／双指捏合缩放，双击复位；支持正交视图和沉浸模式。
- 空格播放／暂停，Esc 关闭面板，⌘I 沉浸，⌘, 设置，⌃⌘F 全屏。
- A320、737-800、777-300ER、787-8/-9/-10、A330-200/-300、A350-900。
  涂装支持中英文、航司代码、地区、收藏和彩绘筛选；清单见 [LIVERY_CATALOG.csv](LIVERY_CATALOG.csv)。
- 可控制频闪、防撞、航行、标志和着陆灯；试闪运行一个完整周期。
- 云层、气流、星空、摄影棚背景；晴朗、多云、雨、雾、雷雨天气。
  天气手动选择，气流为解析可视化，不是 CFD 求解。
- 日照支持手动城市／经纬度、本地时区和时间滑块；定位由系统授权，坐标在本机用于计算。
- HDR/EDR 根据显示器和系统可用余量调整，普通屏幕回退到 SDR；不会修改系统亮度。

默认暂停及 60 帧高精度，可切换节能、标准或最高 120 帧模式。
资源内置，运行时无账号、遥测或资源下载服务。

## 精度与限制

用于外观与灯光可视化，不用于飞行训练或维修。主要包络尺寸按公开资料校准，
曲面、灯位及部分时序没有厂家 CAD 级精度保证。
参考 [LIGHTING_REFERENCE.md](LIGHTING_REFERENCE.md) 和 [MODEL_ACCURACY.md](MODEL_ACCURACY.md)。
涂装包含历史版本及发动机／翼尖适配，不代表现役机队；厦航 787-9 为投影适配。
开发机实时定位曾返回 `locationUnknown`，尚未确认取得实际坐标；可用手动地点。
帧率、功耗、HDR 和定位应在目标设备验证，截图不能证明实际 HDR 峰值。

## 开发与验证

```sh
./scripts/build.sh
swift test
# 仅转换模型或运行几何测试时需要以下依赖
python3 -m venv .venv
.venv/bin/python -m pip install -r scripts/requirements-assets.txt
.venv/bin/python -m unittest discover -s Tests/Geometry
```

参阅 [开发与复现](docs/DEVELOPMENT.md)、[验证记录](docs/VALIDATION.md) 和 [更新记录](CHANGELOG.md)。
1.5.1 的优化、画面对比与闪电调整见 [性能记录](docs/PERFORMANCE.md)。

## 开源与致谢

原创代码采用 **GPL-2.0-only**，见 [LICENSE](LICENSE)。
模型、涂装及可选转换工具保留上游许可。完整项目、用途、固定提交、作者及许可证文件见
**[THIRD_PARTY.md](THIRD_PARTY.md)**。

主要资源来自 FlightGear 社区；应用不链接 FlightGear 引擎。
两款厦航素材来自 MIT 许可的 GEOFS-LiverySelector。Apple 系统框架随 macOS 提供。
航空公司及制造商标志属于各权利人，不表示合作或背书。
分发应用时请保留署名、适用许可证和对应源码；资源包须与对应版本源码一起使用。

欢迎通过 Issues 反馈问题。新增资源须提供来源、固定提交和许可证。

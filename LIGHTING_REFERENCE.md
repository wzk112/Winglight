# 外部灯光核查 · 2026-10-16

本表区分可查证的灯具配置与仍为示意的时序。相同机型可能安装不同供应商或改装灯具，不能仅按“空客双闪、波音单闪”判定所有实机。所有脉冲按模拟时钟取样，不为亮度或过渡延长停留时间。

| 机型 | 当前白色频闪配置 | 已有资料支持 | 仍未核实 |
|---|---|---|---|
| A320 | 两翼双闪，尾部单闪 | Collins 传统翼尖 LED：50 ms 开 / 60 ms 关 / 50 ms 开；尾灯 110 ± 20 ms；白灯 60 ± 5 次/分钟 | 红白相对相位；每架飞机的安装批次 |
| 737-800 | 两翼、尾部各单闪 | 供应商资料支持该机型的翼尖后向白色航行灯配置 | 55 ms 脉宽、60 次/分钟、红白相位均为模拟预设；不代表全部改装构型 |
| 777-300ER | 两翼、尾部各单闪 | Talon 777-200/300 翼尖、尾部频闪与后向航行灯适配资料 | 55 ms 脉宽、60 次/分钟、红白相位为模拟预设 |
| 787-8 | 两翼各一、尾部两侧各一，共 4 个频闪灯 | Boeing 发布的 787 MMEL 草案第 33-4 页列出 4 个白色频闪灯；第 33-5 页列出翼尖及尾部白色位置灯 | 各个脉宽、相位与实际 LED 驱动波形 |
| 787-9 | 同上，灯位按本型独立机身坐标定位 | 同上 | 同上 |
| 787-10 | 同上，灯位按本型独立机身坐标定位 | 同上 | 同上 |
| A330-200 | 两翼双闪、尾部单闪 | Collins A330/A340 清单明确列出 double-flash 翼灯与尾灯组件 | 当前 55 ms 脉宽、110 ms 双脉冲起点间隔、60 次/分钟为示意 |
| A330-300 | 同上，灯位按本型独立坐标定位 | 同上 | 同上 |
| A350-900 | 两翼双闪、尾部单闪示意 | Airbus 机场规划手册 §2-10-0 标出翼尖/尾部频闪及上下红色防撞灯 | 尚未获得确认双闪间隔及脉宽的厂商时序表；双闪本身也保留为暂定示意 |

A320 当前 55 次/分钟对应 Collins 主红灯电源 8ES455967 的 55 ± 5/min 模式，处于白灯 60 ± 5/min 范围的下限。红灯 200 ms 有厂商支持；红白相差半周期只是显示设定。其余机型红灯 120 ms 为模拟值。

## 遮挡核查

9 个机型、17 套几何配置（含不同发动机与厦航投影版本），共 236 个灯具定义。每盏灯以方位角 5°、仰角 10°步进检查光学有效方向，并单独检查发光中心的外向射线。检查使用渲染器同一份三角网格 BVH。

修正 A330-200 尾灯进入尾锥、A350 尾翼照明埋入水平尾翼、787 不同长度版本沿用旧尾灯坐标的问题；增加 787 第二个尾部频闪和波音机翼后向白色航行灯。最终检查没有发现普通外部灯的中心外向射线被模型挡住。尾翼照明的射线本来就应击中垂尾，不视作错误。

扫描是离散角度检查，不等于穷尽所有相机位置。运行时继续使用 13 条有限孔径射线，保留机身、机翼、发动机和尾翼的真实遮挡；没有通过取消深度测试或放大穿透容差掩盖问题。光学配光曲线仍为近似，未获得每个灯具的实测 IES 数据。

## 原始资料

- [Collins A320 LED anti-collision system](https://prd-sc102-cdn.rtx.com/collinsaerospace/-/media/ca/product-assets/files/military-and-defense/lighting/pdfs/anti-collision-lights/06_0010-led-anti-collision-lighting-system-a320.pdf)：本次核对缓存的原始 PDF，在线地址偶尔无法响应。
- [Collins A330/A340 lighting equipment](https://www.collinsaerospace.com/-/media/CA/product-assets/files/military-and-defense/lighting/pdfs/aircraft-overviews/01_0020-airbus-a330-a340-lighting-equipment.pdf?rev=b0067cfa9ef04d42a5362ea21d4a2791)：翼灯 2LA005308-05 / PSU 8ES455438-07、尾灯 2LA005303-05 / PSU 8ES455440-06。
- [Airbus A350 airport planning](https://aircraft.airbus.com/sites/g/files/jlcbta126/files/2024-12/AC_A350_1224.pdf)：§2-10-0 外部照明位置图。
- [Boeing 787 MMEL draft revision 19](https://www.boeing.com/content/dam/boeing/boeingdotcom/commercial/mmel/B-787_Rev_19_DRAFT_FOEB_3_19_25.pdf)：PDF 第 196–197 页（文档 33-4 / 33-5）。仅用于确认灯具数量，不用于运行或签派。
- [Talon Aerospace manufacturer announcements](https://www.talonaerospace.com/news--events.html)：777 翼尖及尾部频闪，737NG/777 后向白色航行灯 STC 配置。
- [Talon TAE1228-5 power supply](https://www.talonaerospace.com/tae1228-5-led-power-supply.html)：可通过引脚选择双闪、延迟等，说明实际改装构型存在差异。

可复查结果见 `Validation/v1.5/occlusion.json`。没有足够资料支持的参数已在应用机型说明内标为模拟值。

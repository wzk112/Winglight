import SwiftUI
import WinglightCore

#if os(macOS)
private let accent = Color(nsColor:NSColor(name:nil) { appearance in
    appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        ? NSColor(red:0.49,green:0.83,blue:0.89,alpha:1)
        : NSColor(red:0.04,green:0.33,blue:0.39,alpha:1)
})
#else
private let accent = Color.accentColor
#endif

struct ContentView: View {
    @ObservedObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        #if os(iOS)
        MobileContentView(state:state)
        #else
        ZStack {
            AircraftStage(state:state).ignoresSafeArea()
                .allowsHitTesting(state.activePanel == nil).accessibilityHidden(state.activePanel != nil)
            Group {
                HStack(alignment:.top,spacing:18) {
                    if !state.focus { sidebar.frame(width:242).transition(.move(edge:.leading).combined(with:.opacity)) }
                    VStack(spacing:16) {
                        if !state.focus { HStack { header.padding(.horizontal,18).padding(.vertical,14).floatingGlass(20);Spacer() } }
                        HStack(alignment:.top) {
                            if state.showDimensions {
                                VStack(alignment:.leading,spacing:6) {
                                    Text("尺寸 · m").fontWeight(.medium)
                                    Text(String(format:"机长 %.2f   翼展 %.2f",state.settings.aircraft.length,state.settings.aircraft.span))
                                    Text(String(format:"机身宽 %.2f   尾翼跨度 %.2f",state.settings.aircraft.bodyWidth,state.settings.aircraft.tailSpan))
                                }.font(.system(size:11,design:.monospaced)).padding(14).floatingGlass(16)
                            }
                            Spacer()
                            SolarSummary(solar:state.solar)
                        }
                        Spacer()
                        HStack(alignment:.center,spacing:12) {
                            transport.padding(.horizontal,14).padding(.vertical,12).floatingGlass(22)
                            Spacer(minLength:8)
                            HStack(spacing:12) {
                                Picker("视角",selection:Binding(get:{state.viewPreset},set:{state.setView($0)})) {
                                    ForEach(ViewPreset.allCases) { Text($0.title).tag($0) }
                                }.labelsHidden().frame(width:108)
                                Button { state.focus.toggle() } label: { Image(systemName:state.focus ? "sidebar.left" : "arrow.up.left.and.arrow.down.right") }.help(state.focus ? "显示控制面板" : "沉浸模式")
                            }.buttonStyle(.borderless).padding(15).floatingGlass(20)
                        }
                    }
                }.padding(18)
            }
            .allowsHitTesting(state.activePanel == nil).accessibilityHidden(state.activePanel != nil)
            if state.liveryLoading && !state.showLiveries {
                VStack { Spacer();HStack(spacing:8) { ProgressView().controlSize(.small);Text("正在载入 \(state.settings.aircraft.modelName)").font(.system(size:12)) }.padding(13).floatingGlass(16);Spacer() }.allowsHitTesting(false)
            }
            if let error=state.rendererError { ContentUnavailableView("无法启动渲染器",systemImage:"display.trianglebadge.exclamationmark",description:Text(error)).padding(24).floatingGlass(24) }
            // Keep the modal host and its z-order alive during removal.
            ZStack {
                if state.showSettings || state.showInfo || state.showLiveries || state.showAircraft {
                    Color.black.opacity(0.18).ignoresSafeArea()
                        .onTapGesture { state.showSettings=false;state.showInfo=false;state.showLiveries=false;state.showAircraft=false }
                        .transition(.opacity).zIndex(1)
                    Group {
                        if state.showAircraft { AircraftPicker(state:state) }
                        else if state.showLiveries { LiveryPicker(state:state) }
                        else if state.showSettings { SettingsView(state:state) }
                        else { info }
                    }.floatingGlass(26,readable:true)
                        .transition(.asymmetric(insertion:.scale(scale:0.96).combined(with:.opacity),removal:.scale(scale:0.98).combined(with:.opacity)))
                        .zIndex(2)
                }
            }.zIndex(20)

        }
        .animation(reduceMotion ? nil : .spring(response:0.34,dampingFraction:0.92),value:state.showAircraft)
        .animation(reduceMotion ? nil : .spring(response:0.34,dampingFraction:0.92),value:state.showLiveries)
        .animation(reduceMotion ? nil : .spring(response:0.34,dampingFraction:0.92),value:state.showSettings)
        .animation(reduceMotion ? nil : .spring(response:0.34,dampingFraction:0.92),value:state.showInfo)
        .animation(reduceMotion ? nil : .easeInOut(duration:0.30),value:state.focus)
        .frame(minWidth:940,minHeight:720)
        .preferredColorScheme(state.interfaceScheme).tint(accent)
        .onChange(of:state.quality) { _,value in UserDefaults.standard.set(value.rawValue,forKey:"renderQuality") }
    #endif
    }
    var sidebar: some View {
        VStack(spacing:12) {
            HStack(spacing:10) {
                Image(systemName:"airplane").font(.system(size:19,weight:.medium)).foregroundStyle(accent)
                Text("Winglight").font(.system(size:18,weight:.semibold,design:.rounded))
                Spacer()
                Button { state.showSettings=true } label: { Image(systemName:"slider.horizontal.3").frame(width:26,height:26).mobileTouchTarget() }
                    .help("设置").accessibilityLabel("设置").keyboardShortcut(",",modifiers:.command)
                Button { state.showInfo=true } label: { Image(systemName:"info.circle").frame(width:20,height:26).mobileTouchTarget() }.help("资料与说明").accessibilityLabel("资料与说明")
            }.buttonStyle(.plain).padding(.horizontal,17).padding(.vertical,13).floatingGlass(18)
            ScrollView {
                WingGlassContainer { VStack(spacing:12) {
                    panel("飞机",icon:"airplane") {
                        Button { state.showAircraft=true } label: {
                            HStack {
                                VStack(alignment:.leading,spacing:5) {
                                    Text(state.settings.aircraft.maker).font(.system(size:9,weight:.semibold)).tracking(1.2).foregroundStyle(.secondary)
                                    Text(state.settings.aircraft.modelName).font(.system(size:19,weight:.semibold,design:.rounded))
                                    Text(state.settings.aircraft.isWidebody ? "宽体客机" : "窄体客机").font(.system(size:10)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName:"chevron.up.chevron.down").font(.system(size:12,weight:.medium)).foregroundStyle(accent)
                            }.padding(12).background(accent.opacity(0.10),in:RoundedRectangle(cornerRadius:12))
                        }.buttonStyle(.plain).accessibilityLabel("选择机型")
                        Button { state.showLiveries=true } label: {
                            HStack {
                                Text("涂装").foregroundStyle(.secondary)
                                Spacer()
                                HStack(spacing:4) {
                                    Text(state.livery.title).lineLimit(1)
                                    if state.liveryLoading { ProgressView().controlSize(.mini) }
                                    else { Image(systemName:"chevron.down").font(.system(size:9,weight:.semibold)) }
                                }.font(.system(size:11,weight:.medium)).foregroundStyle(accent)
                            }.touchRow().contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("打开涂装库")

                    }
                    panel("场景",icon:"sun.horizon") {
                        LazyVGrid(columns:[GridItem(.flexible(),spacing:7),GridItem(.flexible())],spacing:7) {
                            ForEach(Backdrop.allCases) { backdrop in
                                Button { state.backdrop=backdrop } label: {
                                    HStack(spacing:8) { Image(systemName:backdrop.symbol).frame(width:17);Text(backdrop.title);Spacer(minLength:0) }
                                        .font(.system(size:11,weight:.medium)).padding(.horizontal,11).padding(.vertical,10)
                                        .foregroundStyle(state.backdrop == backdrop ? accent : .primary)
                                        .background(state.backdrop == backdrop ? accent.opacity(0.13) : Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:10))
                                }.buttonStyle(.plain).accessibilityLabel(backdrop.title).accessibilityAddTraits(state.backdrop == backdrop ? .isSelected : [])
                            }
                        }
                        Divider().opacity(0.5).padding(.vertical,3)
                        SceneSolarControls(solar:state.solar,environment:$state.environment) {
                            state.settingsTab=2;state.showSettings=true
                        }
                        Divider().opacity(0.5).padding(.vertical,3)
                        switchRow("背景流动",$state.backgroundMotion)
                        switchRow("飞行动态",$state.flightMotion)
                        Picker("天气",selection:$state.weather) { ForEach(SceneWeather.allCases) { Label($0.title,systemImage:$0.symbol).tag($0) } }
                            .disabled(state.backdrop == .studio)
                        if state.backdrop == .studio { Text("摄影棚使用室内灯光").font(.system(size:10)).foregroundStyle(.secondary) }
                    }
                    panel("灯光",icon:"light.beacon.max") {
                        lamp("频闪灯",.white,$state.settings.strobes)
                        lamp("防撞灯",.red,$state.settings.beacons)
                        lamp("航行灯",.green,$state.settings.navigation)
                        lamp("着陆灯",.yellow,$state.settings.landing)
                        lamp("尾翼照明",accent,$state.settings.logo)
                        lamp("客舱照明",.orange,$state.cabinLights)
                    }
                }.padding(.horizontal,1).padding(.vertical,2) }
            }.scrollIndicators(.never).clipped()
        }.font(.system(size:12)).toggleStyle(.switch).platformControlSize()
    }
    private var header: some View {
        HStack(spacing:12) {
            VStack(alignment:.leading,spacing:5) {
                Text(state.settings.aircraft.title).font(.system(size:20,weight:.semibold,design:.rounded))
                Text(state.livery.title).font(.system(size:11)).foregroundStyle(.secondary)
            }
            Rectangle().fill(.primary.opacity(0.10)).frame(width:1,height:29)
            VStack(alignment:.leading,spacing:4) {
                Text(String(format:"%.2f m",state.settings.aircraft.length)).font(.system(size:11,weight:.medium,design:.monospaced))
                Text("机身长度").font(.system(size:9)).foregroundStyle(.secondary)
            }
        }.fixedSize(horizontal:true,vertical:false)
    }
    private var transport: some View {
        HStack(spacing:14) {
            Button { state.togglePlayback() } label: {
                Image(systemName:state.running ? "pause.fill" : "play.fill").font(.system(size:17,weight:.semibold)).frame(width:31,height:31)
            }.buttonStyle(.borderedProminent).buttonBorderShape(.circle).controlSize(.large)
                .help(state.running ? "暂停 · 空格" : "播放 · 空格").accessibilityLabel(state.running ? "暂停" : "播放").disabled(state.rendererError != nil)
            VStack(alignment:.leading,spacing:4) {
                Text(state.running ? "正在播放" : "播放场景").font(.system(size:12,weight:.semibold))
                Text(state.running ? (state.backdrop.title + " · " + (state.flightMotion ? "飞行动效" : "固定机位")) : "空格播放 · 拖动旋转").font(.system(size:10)).foregroundStyle(.secondary)
            }.frame(minWidth:115,alignment:.leading)
            Rectangle().fill(.primary.opacity(0.10)).frame(width:1,height:26)
            Button { state.testFlash() } label: { Label("试闪",systemImage:"bolt.fill").font(.system(size:11,weight:.medium)) }.buttonStyle(.plain).padding(.horizontal,3)
        }
    }
    private func panel<Content: View>(_ title: String,icon: String,@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Label(title,systemImage:icon).font(.system(size:10,weight:.semibold)).foregroundStyle(.secondary).padding(.bottom,1)
            content()
        }.padding(15).frame(maxWidth:.infinity,alignment:.leading).floatingGlass(20)
    }
    private func lamp(_ title: String,_ color: Color,_ binding: Binding<Bool>) -> some View {
        HStack(spacing:9) {
            Circle().fill(color.opacity(binding.wrappedValue ? 0.85 : 0.2)).frame(width:6,height:6)
                .overlay { Circle().strokeBorder(.primary.opacity(0.12),lineWidth:0.5) }
            Text(title);Spacer();Toggle(title,isOn:binding).labelsHidden()
        }.touchRow()
    }
    private func switchRow(_ title: String,_ binding: Binding<Bool>) -> some View {
        HStack { Text(title);Spacer();Toggle(title,isOn:binding).labelsHidden() }.touchRow()
    }
    var info: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Winglight " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版")).font(.title2)
            Text("原生飞机三维可视化应用。模型来自 FlightGear 开源项目，已校正机长、翼展和机身宽度；其他曲面与灯位仍为近似。")
            Text("内置 \(Livery.catalog.count) 款机型专用涂装，支持搜索与收藏。涵盖 9 个机型；787 与 A330 按涂装搭配不同发动机。历史涂装、特殊彩绘及适配限制见列表。")
            Text("A320 翼灯为 50 ms 亮、60 ms 灭、50 ms 亮，尾闪 110 ms。A330 已核实翼尖双闪配置，其他机型的精确脉宽与相位尚未核实。亮度设置不改变时序。")
            Text("气流采用绕体流管和尾涡近似，颜色仅辅助辨认流动变化，不是 CFD 计算结果；飞机摆动、风扇及背景为视觉动画。日照使用 NOAA / Meeus 太阳位置算法，日出日落采用标准大气折射，不包含地形。天气为手动视觉模拟，机头方向定义为北。")
            HStack {
                Link("模型与许可证",destination:URL(string:"https://github.com/legoboyvdlp/A320-family")!)
                Link("太阳计算依据",destination:URL(string:"https://gml.noaa.gov/grad/solcalc/calcdetails.html")!)
                Spacer();Button("完成") { state.showInfo=false }.keyboardShortcut(.defaultAction)
            }
        }.font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(5).padding(28).desktopPanel(width:590)
    }
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing:0) {
            HStack { Text("设置").font(.title2);Spacer();Button("完成") { state.showSettings=false }.keyboardShortcut(.defaultAction) }.padding(24)
            Picker("设置类别",selection:$state.settingsTab) {
                Label("画面",systemImage:"display").tag(0)
                Label("灯光",systemImage:"light.beacon.max").tag(1)
                Label("时间与地点",systemImage:"sun.max").tag(2)
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal,24).padding(.bottom,12)
            Group {
                if state.settingsTab == 0 { Form {
                    Section("渲染") {
                        Picker("画质",selection:$state.quality) { ForEach(RenderQuality.allCases) { Text($0.title).tag($0) } }
                        LabeledContent("内部分辨率",value:state.renderResolution)
                        LabeledContent("抗锯齿",value:"\(state.quality.samples)× MSAA")
                        Text(state.quality == .ultra ? "高精度以 Retina 的两倍宽高渲染，再缩小显示。" : "使用屏幕原生 Retina 分辨率。").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("动态") {
                        slider("动效强度",value:$state.motionIntensity,range:0.35...1.75,format:"%.0f%%",scale:100)
                        Text("调整飞机起伏、倾斜与环境流动；频闪灯时序不变。").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("显示") {
                        Toggle("模型网格",isOn:$state.wireframe)
                        Toggle("尺寸标注",isOn:$state.showDimensions)
                        Toggle("摄影棚网格",isOn:$state.grid)
                        LabeledContent("屏幕",value:state.displayName)
                    }
                }.formStyle(.grouped).scrollContentBackground(.hidden) }
                else if state.settingsTab == 1 { Form {
                    Section("灯光") {
                        Toggle("HDR 闪光",isOn:$state.hdr)
                        slider("强度",value:$state.strength,range:0.1...1,format:"%.0f%%",scale:100)
                        slider("灯芯大小",value:$state.coreSize,range:2...8,format:"%.1f",scale:1)
                        slider("光晕",value:$state.glow,range:0.4...1.8,format:"%.1f×",scale:1)
                        LabeledContent("当前高亮余量",value:String(format:"%.2f× SDR",state.headroom))
                        Text("高亮余量由屏幕与系统控制。所有调节保持原始闪光时长。").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("时序") {
                        Text(state.settings.aircraft.patternDescription+"。"+(state.settings.aircraft == .airbus ? "翼灯 50 / 60 / 50 ms；尾闪 110 ms；红灯 200 ms。" : "脉宽、周期及红白相位为模拟设定。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.formStyle(.grouped).scrollContentBackground(.hidden) }
                else { SolarSettingsPane(solar:state.solar) }
            }.id(state.settingsTab).transition(.opacity)
                .animation(reduceMotion ? nil : .easeInOut(duration:0.20),value:state.settingsTab)
                .padding(.horizontal,16).padding(.bottom,20)
        }.desktopPanel(width:590,height:570).preferredColorScheme(state.interfaceScheme).tint(accent)

    }
    private func slider(_ label: String,value: Binding<Double>,range: ClosedRange<Double>,format: String,scale: Double) -> some View {
        VStack(alignment:.leading,spacing:6) {
            HStack { Text(label);Spacer();Text(String(format:format,value.wrappedValue*scale)).monospacedDigit().foregroundStyle(.secondary) }
            GlassSlider(value:value,range:range,label:label,formattedValue:String(format:format,value.wrappedValue*scale))
        }
    }
}

struct WingGlassContainer<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        if #available(macOS 26.0, iOS 26.0, *) { GlassEffectContainer(spacing:16) { content } }
        else { content }
    }
}
extension View {
    @ViewBuilder func floatingGlass(_ radius: CGFloat,readable: Bool = false) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            self.glassEffect((readable ? Glass.regular : Glass.clear).tint(.primary.opacity(0.035)),in:RoundedRectangle(cornerRadius:radius)).shadow(color:.black.opacity(0.12),radius:16,y:6)
        } else {
            self.background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:radius))
        }
    }
}

struct SceneTimeControl: View {
    @ObservedObject var solar: SolarController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment:.leading,spacing:7) {
            HStack {
                Text(solar.returningToNow ? "正在恢复" : (solar.manualDate == nil ? "当前时间" : "手动时间")).foregroundStyle(.secondary)
                Spacer()
                Text(solar.clock(solar.date)).monospacedDigit().fontWeight(.medium)
            }
            GlassSlider(value:Binding(get:{min(23.9833,solar.hour)},set:{solar.previewHour($0)}),range:0...23.9833,label:"场景时间",formattedValue:solar.clock(solar.date),step:1.0/60,onEditingEnded:{solar.endScrubbing()})
                .disabled(solar.coordinate == nil)
            HStack {
                Text("00:00");Spacer();Text("12:00");Spacer();Text("23:59")
            }.font(.system(size:9)).foregroundStyle(.secondary)
            if solar.coordinate == nil { Text("选定地点后可拖动时间").font(.caption).foregroundStyle(.secondary) }
            else {
                Button { solar.restoreCurrentTime(animated:!reduceMotion) } label: { Label("恢复当前时间",systemImage:"clock.arrow.circlepath") }
                    .buttonStyle(.plain).disabled(solar.manualDate == nil || solar.returningToNow)
            }
        }.font(.system(size:11)).onDisappear { solar.endScrubbing() }
    }
}

struct SolarSummary: View {
    @ObservedObject var solar: SolarController
    var body: some View {
        if solar.followsClock && solar.position != nil {
            VStack(alignment:.trailing,spacing:5) {
                Text(solar.locationName+" · "+solar.clock(solar.date)).font(.system(size:12,weight:.medium)).monospacedDigit()
                HStack(spacing:10) {
                    Label(solar.clock(solar.events?.sunrise),systemImage:"sunrise")
                    Label(solar.clock(solar.events?.sunset),systemImage:"sunset")
                }.font(.system(size:10)).foregroundStyle(.secondary)
            }.padding(12).floatingGlass(16)
        }
    }
}
private struct SceneSolarControls: View {
    @ObservedObject var solar: SolarController
    @Binding var environment: SkyEnvironment
    var showLocation: () -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack { Text("按时间计算日照");Spacer();Toggle("按时间计算日照",isOn:$solar.followsClock).labelsHidden() }.touchRow()
            if solar.followsClock { locationControl;SceneTimeControl(solar:solar) }
            else { Picker("时段",selection:$environment) { ForEach(SkyEnvironment.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).labelsHidden() }
        }
    }
    private var locationControl: some View {
        VStack(alignment:.leading,spacing:8) {
            if solar.requesting {
                HStack(spacing:7) {
                    ProgressView().controlSize(.mini)
                    Text(solar.requestTitle).font(.system(size:11))
                    Spacer(minLength:0)
                    Button("取消") { solar.cancelLocation() }.buttonStyle(.plain).foregroundStyle(accent)
                }
            } else if solar.coordinate != nil {
                Button { showLocation() } label: {
                    HStack { Label(solar.locationName,systemImage:solar.usesMacLocation ? "location.fill" : "mappin");Spacer();Text(solar.phase).foregroundStyle(.secondary);Image(systemName:"chevron.right").font(.system(size:8,weight:.semibold)) }
                }.buttonStyle(.plain)
            } else {
                HStack(spacing:8) {
                    Button { solar.locate() } label: { Label(solar.locationIssue ? "重试定位" : "使用定位",systemImage:"location") }
                    Button("选城市") { showLocation() }
                }.buttonStyle(.bordered).controlSize(.small)
            }
            if solar.coordinate == nil || solar.locationIssue {
                Text(solar.locationIssue ? "未取得位置，可重试或手动选城市。" : solar.status).font(.system(size:10)).foregroundStyle(solar.locationIssue ? Color.primary.opacity(0.72) : Color.secondary).fixedSize(horizontal:false,vertical:true).lineSpacing(2)
            }
        }
    }
}
private struct SolarSettingsPane: View {
    @ObservedObject var solar: SolarController
    @State private var latitude=0.0
    @State private var longitude=0.0
    private var cityButtons: some View {
        HStack {
            Button("墨尔本") { solar.setLocation(latitude:-37.8136,longitude:144.9631,name:"墨尔本",timeZoneID:"Australia/Melbourne") }.accessibilityIdentifier("cityMelbourne")
            Button("北京") { solar.setLocation(latitude:39.9042,longitude:116.4074,name:"北京",timeZoneID:"Asia/Shanghai") }
            Button("伦敦") { solar.setLocation(latitude:51.5074,longitude:-0.1278,name:"伦敦",timeZoneID:"Europe/London") }
        }.buttonStyle(.bordered)
    }
    var body: some View {
Form {
                    #if os(iOS)
                    Section("常用城市") { cityButtons }
                    #endif
                    Section("日照") {
                        Toggle("按时间计算日照",isOn:$solar.followsClock)
                        SceneTimeControl(solar:solar)
                        HStack {
                            Label(solar.locationName,systemImage:"location")
                            Spacer()
                            if solar.requesting {
                                ProgressView().controlSize(.small)
                                Button("取消") { solar.cancelLocation() }
                            } else { Button(solar.locationIssue ? "重试定位" : "使用设备定位") { solar.locate() } }
                        }
                        if !solar.status.isEmpty { Text(solar.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
                        HStack { LabeledContent("系统授权",value:solar.authorizationLabel);Spacer();Button("打开定位设置") { solar.openLocationSettings() } }
                        Text("定位由系统提供。授权后仍无结果时，可以手动选城市，日照计算同样有效。").font(.caption).foregroundStyle(.secondary)
                        HStack { LabeledContent("日出",value:solar.clock(solar.events?.sunrise));LabeledContent("日落",value:solar.clock(solar.events?.sunset)) }
                        if let p=solar.position { LabeledContent("太阳高度",value:String(format:"%.1f°",p.elevation)) }
                    }
                    Section("手动地点") {
                        #if os(macOS)
                        cityButtons
                        #endif
                        TextField("纬度",value:$latitude,format:.number.precision(.fractionLength(4)))
                        TextField("经度",value:$longitude,format:.number.precision(.fractionLength(4)))
                        Button("应用经纬度") { solar.timeZone = .current;solar.setLocation(latitude:latitude,longitude:longitude,name:"自定义地点") }
                        Text("跟随当前时间时每 30 秒更新，手动时间会保持。位置仅用于本机计算；日出日落按所选地点时区显示，自定义经纬度使用系统时区。").font(.caption).foregroundStyle(.secondary)
                    }
                }.formStyle(.grouped).scrollContentBackground(.hidden)            .onAppear { latitude=solar.coordinate?.latitude ?? 0;longitude=solar.coordinate?.longitude ?? 0 }
            .onChange(of:solar.coordinate?.latitude) { _,value in if let value { latitude=value } }
            .onChange(of:solar.coordinate?.longitude) { _,value in if let value { longitude=value } }
    }
}

extension View {
    @ViewBuilder func desktopPanel(width: CGFloat, height: CGFloat? = nil) -> some View {
        #if os(macOS)
        self.frame(width:width,height:height)
        #else
        self.frame(maxWidth:.infinity,maxHeight:height == nil ? nil : .infinity)
        #endif
    }
    @ViewBuilder func panelViewport(height: CGFloat) -> some View {
        #if os(macOS)
        self.frame(height:height)
        #else
        self.frame(maxHeight:.infinity)
        #endif
    }
}

extension View {
    @ViewBuilder func platformControlSize() -> some View {
        #if os(iOS)
        self.controlSize(.regular)
        #else
        self.controlSize(.mini)
        #endif
    }
    @ViewBuilder func touchRow() -> some View {
        #if os(iOS)
        self.frame(minHeight:44)
        #else
        self.frame(minHeight:22)
        #endif
    }
}

extension View {
    @ViewBuilder func mobileTouchTarget() -> some View {
        #if os(iOS)
        self.frame(minWidth:44,minHeight:44).contentShape(Rectangle())
        #else
        self
        #endif
    }
}

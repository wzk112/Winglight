import SwiftUI
import WinglightCore

struct MobileContentView: View {
    @ObservedObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheetVisible=false
    @State private var sheetDismissing=false
    var body: some View {
        GeometryReader { proxy in
            let wide=proxy.size.width>=900 && proxy.size.height>=580
            HStack(spacing:0) {
                if wide && !state.focus {
                    ContentView(state:state).sidebar.padding(16).frame(width:300)
                        .background(.ultraThinMaterial)
                        .accessibilityIdentifier("tabletSidebar")
                }
                ZStack {
                    AircraftStage(state:state).ignoresSafeArea()
                    VStack(spacing:12) {
                        if !state.focus { header(compact:!wide) }
                        if state.showDimensions {
                            Text(String(format:"机长 %.2f m · 翼展 %.2f m\n机身宽 %.2f m · 尾翼跨度 %.2f m",state.settings.aircraft.length,state.settings.aircraft.span,state.settings.aircraft.bodyWidth,state.settings.aircraft.tailSpan))
                                .font(.caption.monospaced()).padding(12).floatingGlass(16)
                        }
                        Spacer(minLength:0)
                        if let error=state.liveryError { Text(error).font(.caption).padding(12).floatingGlass(16) }
                        if state.liveryLoading {
                            HStack { ProgressView();Text("正在载入 \(state.settings.aircraft.modelName)").font(.caption) }.padding(12).floatingGlass(16)
                        }
                        transport(wide:wide)
                    }.padding(wide ? 20 : 12)
                    if let error=state.rendererError {
                        ContentUnavailableView("无法启动渲染器",systemImage:"display.trianglebadge.exclamationmark",description:Text(error))
                            .padding().background(.regularMaterial)
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            }
            .sheet(isPresented:Binding(get:{sheetVisible},set:{ value in
                if !value && !sheetDismissing { state.dismissPanel();sheetDismissing=true }
                sheetVisible=value
            }),onDismiss:{
                sheetDismissing=false
                // Honor a panel requested while UIKit was dismissing the old one.
                if state.activePanel != nil { sheetVisible=true }
            }) {
                NavigationStack {
                    Group {
                        switch state.activePanel {
                        case .aircraft: AircraftPicker(state:state)
                        case .liveries: LiveryPicker(state:state)
                        case .settings: SettingsView(state:state)
                        case .info: ScrollView { ContentView(state:state).info }
                        default: ContentView(state:state).sidebar.padding(16)
                        }
                    }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement:.topBarLeading) {
                            if state.activePanel != .controls && !wide {
                                Button { state.openControls() } label: { Label("控制",systemImage:"chevron.left") }
                            }
                        }
                        ToolbarItem(placement:.topBarTrailing) { Button("关闭") { state.dismissPanel() }.accessibilityIdentifier("dismissPanel") }
                    }
                }
                .presentationDetents([.large]).presentationDragIndicator(.visible)
                .preferredColorScheme(state.interfaceScheme)
            }
        }
        .background(Color(red:0.018,green:0.027,blue:0.039))
        .preferredColorScheme(state.interfaceScheme)
        .tint(Color(red:0.22,green:0.65,blue:0.73))
        .animation(reduceMotion ? nil : .easeInOut(duration:0.25),value:state.focus)
        .onChange(of:state.quality) { _,value in UserDefaults.standard.set(value.rawValue,forKey:"renderQuality") }
        .onChange(of:scenePhase) { _,_ in state.renderRequests.send() }
        .onChange(of:state.activePanel) { _,panel in
            if panel == nil {
                if sheetVisible { sheetDismissing=true;sheetVisible=false }
            } else if !sheetVisible && !sheetDismissing { sheetVisible=true }
        }
        .background { keyboardActions }
    }
    private func header(compact: Bool) -> some View {
        HStack(alignment:.top,spacing:8) {
            VStack(alignment:.leading,spacing:5) {
                Button { state.showAircraft=true } label: {
                    Label(state.settings.aircraft.modelName,systemImage:"airplane").font(.headline)
                }.buttonStyle(.plain).accessibilityLabel("选择机型")
                Button { state.showLiveries=true } label: {
                    Text(state.livery.title).font(.caption).lineLimit(1).frame(minHeight:32).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("打开涂装库")
            }.padding(14).floatingGlass(20)
            Spacer(minLength:0)
            if compact {
                Button { state.openControls() } label: { Image(systemName:"slider.horizontal.3").frame(width:46,height:46).contentShape(Rectangle()) }
                    .floatingGlass(16).accessibilityLabel("控制面板").accessibilityIdentifier("openControls")
            } else { SolarSummary(solar:state.solar) }
        }
    }
    private func transport(wide: Bool) -> some View {
        HStack(spacing:8) {
            Button { state.togglePlayback() } label: {
                Image(systemName:state.running ? "pause.fill" : "play.fill").frame(width:46,height:46).contentShape(Rectangle())
            }.buttonStyle(.borderedProminent).buttonBorderShape(.circle)
                .accessibilityLabel(state.running ? "暂停" : "播放").disabled(state.rendererError != nil)
            Button { state.testFlash() } label: { Image(systemName:"bolt.fill").frame(width:44,height:44).contentShape(Rectangle()) }.accessibilityLabel("试闪")
            Spacer(minLength:0)
            Menu {
                ForEach(ViewPreset.allCases) { preset in Button(preset.title) { state.setView(preset) } }
                Divider()
                Button("停止并复位") { state.stop() }
            } label: { Image(systemName:"view.3d").frame(width:44,height:44).contentShape(Rectangle()) }.accessibilityLabel("视角")
            Button { state.focus.toggle() } label: {
                Image(systemName:state.focus ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").frame(width:44,height:44).contentShape(Rectangle())
            }.accessibilityLabel(state.focus ? "退出沉浸模式" : "沉浸模式")
        }.buttonStyle(.plain).padding(10).floatingGlass(24)
            .frame(maxWidth:wide ? 440 : 360)
    }
    private var keyboardActions: some View {
        Group {
            Button("播放 / 暂停") { state.togglePlayback() }.keyboardShortcut(.space,modifiers:[])
            Button("关闭面板") { state.dismissPanel() }.keyboardShortcut(.escape,modifiers:[])
            Button("设置") { state.showSettings=true }.keyboardShortcut(",",modifiers:.command)
            Button("沉浸模式") { state.focus.toggle() }.keyboardShortcut("i",modifiers:.command)
        }.hidden().accessibilityHidden(true)
    }
}

import AppKit
import Darwin
import SwiftUI
import WinglightCore

@main struct WinglightApplication {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var state = AppState()
    var window: NSWindow?
    var keyboardMonitor: Any?
    private var diagnosticClock: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of:flag), args.indices.contains(i+1) else { return nil }; return args[i+1]
        }
        if let directory=value("--audit-performance") {
            NSApp.setActivationPolicy(.prohibited)
            Task {
                let success=await PerformanceAudit.run(directory:directory,frames:Int(value("--audit-frames") ?? "120") ?? 120,filter:value("--audit-filter"))
                exit(success ? 0 : 1)
            }
            return
        }
        if let directory=value("--audit-flow") { FlowAudit.run(directory:directory);NSApp.terminate(nil);return }
        if let directory=value("--audit-lights") { LightingAudit.run(directory:directory);NSApp.terminate(nil);return }
        if let directory=value("--audit-catalog") {
            NSApp.setActivationPolicy(.prohibited)
            Task { await CatalogAudit.run(directory:directory,filter:value("--audit-filter"));NSApp.terminate(nil) }
            return
        }
        if let directory=value("--audit-models") {
            NSApp.setActivationPolicy(.prohibited)
            Task { await CatalogAudit.run(directory:directory,filter:value("--audit-filter"),details:true);NSApp.terminate(nil) }
            return
        }
        state.select(Aircraft.parse(value("--aircraft") ?? "airbus") ?? .airbus)
        if args.contains("--sdr") { state.hdr = false }
        if args.contains("--underside") { state.setView(.bottom) }
        if let t = value("--qa-time").flatMap(Double.init) { state.qaTime = t }
        state.qaOutput = value("--qa-output")
        if let name = value("--view"), let preset = ViewPreset(rawValue:name) { state.setView(preset) }
        if let yaw = value("--yaw").flatMap(Double.init) { state.viewPreset = .orbit; state.cameraYaw = yaw }
        if let pitch = value("--pitch").flatMap(Double.init) { state.viewPreset = .orbit; state.cameraPitch = pitch }
        if let name = value("--environment"),let mode = SkyEnvironment(rawValue:name) { state.environment = mode;state.solar.followsClock=false }
        if let lat=value("--latitude").flatMap(Double.init),let lon=value("--longitude").flatMap(Double.init) {
            state.solar.setLocation(latitude:lat,longitude:lon,name:"测试地点",timeZoneID:value("--timezone"),persist:false);state.solar.followsClock=true
            if let stamp=value("--date"),let date=ISO8601DateFormatter().date(from:stamp) { state.solar.refresh(at:date) }
        }
        if let name = value("--background"),let mode = Backdrop(rawValue:name) { state.backdrop = mode }
        if let name = value("--weather"),let weather=SceneWeather(rawValue:name) { state.weather=weather }
        if args.contains("--no-cabin") { state.cabinLights=false }
        if let name = value("--quality"),let quality = RenderQuality(rawValue:name) { state.quality = quality }
        if let code=value("--livery"),let livery=Livery.matching(code,aircraft:state.settings.aircraft) { state.livery=livery }
        if args.contains("--neutral") { state.livery = .neutral }
        if args.contains("--no-logo") { state.settings.logo = false }
        if args.contains("--no-motion") { state.flightMotion = false }
        if args.contains("--no-background-motion") { state.backgroundMotion = false }
        if let distance = value("--distance").flatMap(Double.init) { state.cameraDistance = min(220,max(32,distance)) }
        state.idleOutput = value("--idle-output")
        state.perfOutput = value("--perf-output")
        if let frames = value("--perf-frames").flatMap(Int.init) { state.perfFrames = max(30,frames) }
        if args.contains("--landing") { state.settings.landing = true }
        if args.contains("--autoplay") { state.togglePlayback() }
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1180,height:820),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title = "Winglight · 飞机灯光模拟"
        window.minSize = NSSize(width:940,height:744)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named:.darkAqua)
        window.backgroundColor = NSColor(red:0.018,green:0.027,blue:0.039,alpha:1)
        window.colorSpace = NSColorSpace.extendedSRGB
        window.contentView = NSHostingView(rootView:ContentView(state:state))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window; state.window = window
        if args.contains("--perf-scrub") {
            state.solar.setLocation(latitude:-37.8136,longitude:144.9631,name:"测试地点",timeZoneID:"Australia/Melbourne",persist:false)
            let start=CACurrentMediaTime()
            let timer=Timer(timeInterval:1/60,repeats:true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.state.solar.setHour((CACurrentMediaTime()-start).truncatingRemainder(dividingBy:8)*3)
                }
            }
            diagnosticClock=timer;RunLoop.main.add(timer,forMode:.common)
        }
        installMenu()
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            if let self,event.keyCode == 53,self.state.showInfo || self.state.showSettings || self.state.showLiveries || self.state.showAircraft {
                self.state.showInfo=false;self.state.showSettings=false;self.state.showLiveries=false;self.state.showAircraft=false;return nil
            }
            guard let self, event.window === self.window, !self.state.showInfo, !self.state.showSettings, !self.state.showLiveries, !self.state.showAircraft,
                  event.modifierFlags.intersection([.command,.control,.option]).isEmpty else { return event }
            if event.keyCode == 49 && !event.isARepeat { self.state.togglePlayback(); return nil }
            if event.keyCode == 53 { self.state.stop(); return nil }
            return event
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) } }
    @objc func about() { state.showInfo = true }
    @objc func settings() { state.showSettings = true }
    @objc func toggle() { state.togglePlayback() }
    @objc func stop() { state.stop() }
    @objc func fullScreen() { window?.toggleFullScreen(nil) }
    @objc func focus() { state.focus.toggle() }
    func installMenu() {
        let root = NSMenu()
        let appItem = NSMenuItem(); root.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        let about = NSMenuItem(title:"关于 Winglight",action:#selector(about),keyEquivalent:""); about.target = self; appMenu.addItem(about)
        let settings = NSMenuItem(title:"设置…",action:#selector(settings),keyEquivalent:",");settings.target = self;appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title:"隐藏 Winglight",action:#selector(NSApplication.hide(_:)),keyEquivalent:"h"))
        appMenu.addItem(NSMenuItem(title:"退出 Winglight",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q"))
        let simItem = NSMenuItem(title:"模拟",action:nil,keyEquivalent:""); root.addItem(simItem)
        let simMenu = NSMenu(title:"模拟"); simItem.submenu = simMenu
        for (name,action,key) in [("播放 / 暂停",#selector(toggle),"p"),("停止",#selector(stop),"."),("沉浸模式",#selector(focus),"i")] {
            let item = NSMenuItem(title:name,action:action,keyEquivalent:key); item.target = self; simMenu.addItem(item)
        }
        let view = NSMenuItem(title:"窗口",action:nil,keyEquivalent:""); root.addItem(view)
        let viewMenu = NSMenu(title:"窗口"); view.submenu = viewMenu
        let fs = NSMenuItem(title:"进入 / 退出全屏",action:#selector(fullScreen),keyEquivalent:"f"); fs.keyEquivalentModifierMask = [.command,.control]; fs.target = self; viewMenu.addItem(fs)
        viewMenu.addItem(NSMenuItem(title:"最小化",action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m"))
        NSApp.mainMenu = root
    }
}

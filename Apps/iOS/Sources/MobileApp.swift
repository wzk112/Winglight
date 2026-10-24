import SwiftUI
import WinglightCore

@main struct WinglightMobileApp: App {
    var body: some Scene {
        WindowGroup { MobileWindow() }
    }
}

private struct MobileWindow: View {
    @StateObject private var state=AppState()
    @State private var configured=false
    var body: some View {
        ContentView(state:state).onAppear { configureDiagnostics() }
    }
    private func configureDiagnostics() {
        guard !configured else { return };configured=true
        state.select(.airbus)
        let args=ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let i=args.firstIndex(of:flag),args.indices.contains(i+1) else { return nil };return args[i+1]
        }
        if args.contains("--uitesting") {
            state.solar.followsClock=false
            state.quality = .efficient
            state.select(.airbus)
        }
        if let aircraft=value("--aircraft").flatMap(Aircraft.parse) { state.select(aircraft) }
        if let name=value("--weather").flatMap(SceneWeather.init(rawValue:)) { state.weather=name }
        if let name=value("--background").flatMap(Backdrop.init(rawValue:)) { state.backdrop=name }
        if let name=value("--quality").flatMap(RenderQuality.init(rawValue:)) { state.quality=name }
        if let name=value("--view").flatMap(ViewPreset.init(rawValue:)) { state.setView(name) }
        if let time=value("--qa-time").flatMap(Double.init) { state.qaTime=time;state.solar.followsClock=false }
        if args.contains("--qa-output") { state.qaOutput=URL.documentsDirectory.appending(path:"render-qa.json").path }
        if args.contains("--autoplay"),!state.running { state.togglePlayback() }
    }
}

import AppKit
import SwiftUI
import Combine
import WinglightCore

@MainActor final class AppState: ObservableObject {
    let solar: SolarController
    let renderRequests=PassthroughSubject<Void,Never>()
    private var lastSolarScheme: ColorScheme?
    private var solarSubscription: AnyCancellable?
    convenience init() { self.init(solar:SolarController()) }
    init(solar: SolarController) {
        self.solar=solar;lastSolarScheme=interfaceScheme
        solarSubscription=solar.sceneChanges.sink { [weak self] _ in
            guard let self else { return }
            self.updateMotion()
            if self.lastSolarScheme != self.interfaceScheme {
                self.lastSolarScheme=self.interfaceScheme;self.objectWillChange.send()
            }
            self.renderRequests.send()
        }
    }
    var baseEnvironment: Float { solar.followsClock ? (solar.position?.environment ?? environment.index) : environment.index }
    var environmentValue: Float { (qaTime != nil ? baseEnvironment : Float(daylightBlend.value(at:CACurrentMediaTime())))*(1-backgroundWeights.z) }
    var interfaceScheme: ColorScheme { if backdrop == .stars { return .dark };return baseEnvironment > 1.35 || ((backdrop == .flow || backdrop == .studio) && baseEnvironment > 0.75) ? .light : .dark }
    var sunDirection: SIMD3<Float> { solar.followsClock ? (solar.position?.direction ?? SIMD3(-0.52,0.75,-0.40)) : SIMD3(-0.52,0.75,-0.40) }
    @Published var settings = LightSettings()
    @Published var running = false
    @Published var hdr = true
    @Published var strength = 1.0
    @Published var glow = 1.0
    @Published var coreSize = 5.0
    @Published var viewPreset = ViewPreset.orbit
    @Published var cameraYaw = -0.65
    var auditCameraTarget: SIMD3<Float>? = nil
    var auditUnlit = false
    @Published var cameraPitch = 0.38
    @Published var cameraDistance = 68.0
    @Published var wireframe = false
    @Published var showDimensions = false
    @Published var labels = true
    @Published var grid = true
    @Published var cabinLights = true
    @Published var weather = SceneWeather.clear {
        didSet { let now=CACurrentMediaTime();for i in 0..<4 { weatherBlend[i].set(weather.parameters[i],at:now,duration:1.2) } }
    }
    private var weatherBlend=[EasedValue(0.10),EasedValue(0),EasedValue(0),EasedValue(0)]
    var weatherValue: SIMD4<Float> {
        let values=qaTime != nil ? SIMD4<Float>((0..<4).map { Float(weather.parameters[$0]) }) : SIMD4<Float>((0..<4).map { Float(weatherBlend[$0].value(at:CACurrentMediaTime())) })
        return values*(1-backgroundWeights.w)
    }
    @Published var focus = false
    @Published var headroom = 1.0
    @Published var potential = 1.0
    @Published var renderResolution = ""
    @Published var displayName = "正在检测屏幕"
    @Published var rendererError: String?
    @Published var showInfo = false
    @Published var showSettings = false
    @Published var settingsTab = 0
    @Published var livery = Livery.airChina { didSet { settings.geometry=sceneGeometry } }
    var assetID: String { livery.asset(for:settings.aircraft) }
    var sceneGeometry: AircraftGeometry { AircraftGeometry.catalog[assetID] ?? settings.aircraft.geometry }
    var orbitDistance: Double { 68 * max(1,settings.aircraft.length/39.47,settings.aircraft.span/35.79) }
    @Published var showAircraft = false
    @Published var showLiveries = false
    @Published var liveryLoading = false
    @Published var liveryError: String?
    @Published var favoriteLiveries = Set(UserDefaults.standard.stringArray(forKey:"favoriteLiveries") ?? [])
    func chooseLivery(_ value: Livery) {
        livery=value;liveryError=nil
        UserDefaults.standard.set(value.id,forKey:"livery-"+settings.aircraft.rawValue)
    }
    func toggleFavorite(_ value: Livery) {
        if favoriteLiveries.contains(value.id) { favoriteLiveries.remove(value.id) } else { favoriteLiveries.insert(value.id) }
        UserDefaults.standard.set(Array(favoriteLiveries).sorted(),forKey:"favoriteLiveries")
    }
    @Published var environment = SkyEnvironment.day { didSet { daylightBlend.set(Double(baseEnvironment),at:CACurrentMediaTime(),duration:0.8) } }
    @Published var backdrop = Backdrop.clouds {
        didSet {
            guard oldValue != backdrop else { return }
            let now=CACurrentMediaTime()
            for i in 0..<4 { backdropBlend[i].set(i == Int(backdrop.index) ? 1 : 0,at:now) }
        }
    }
    @Published var motionIntensity = 1.0
    @Published var flightMotion = true {
        didSet { guard oldValue != flightMotion else { return };let now=CACurrentMediaTime();updateMotion(at:now);flightBlend.set(flightMotion ? 1 : 0,at:now,duration:1.0) }
    }
    @Published var backgroundMotion = true {
        didSet { guard oldValue != backgroundMotion else { return };let now=CACurrentMediaTime();updateMotion(at:now);backgroundSpeed.set(backgroundMotion ? 1 : 0,at:now,duration:1.0) }
    }
    @Published var quality = RenderQuality(rawValue:UserDefaults.standard.string(forKey:"renderQuality") ?? "") ?? .ultra
    @Published var testStart: Double?
    weak var window: NSWindow?
    private var origin = CACurrentMediaTime()
    private var elapsed = 0.0
    private var daylightBlend=EasedValue(2)
    private var daylightTarget: Float=2
    private var flightBlend=EasedValue(1),backgroundSpeed=EasedValue(1)
    private var backdropBlend=[EasedValue(1),EasedValue(0),EasedValue(0),EasedValue(0)]
    private var motionStamp: Double?
    private var flightPhase=0.0,backgroundPhase=0.0
    private(set) var flightAmount=1.0
    private(set) var backgroundWeights=SIMD4<Float>(1,0,0,0)
    var flightTime: Double { qaTime ?? flightPhase }
    func updateMotion(at now: Double = CACurrentMediaTime()) {
        if qaTime != nil {
            flightAmount=flightMotion ? 1 : 0
            backgroundWeights = .zero;backgroundWeights[Int(backdrop.index)]=1
            motionStamp=now;return
        }
        if baseEnvironment != daylightTarget { daylightTarget=baseEnvironment;daylightBlend.set(Double(daylightTarget),at:now,duration:solar.manualDate != nil || solar.returningToNow ? 0 : 0.8) }
        if let last=motionStamp,running {
            // Do not catch up invisible time after the display or app sleeps.
            let from=max(last,now-0.10)
            backgroundPhase += backgroundSpeed.integral(from:from,to:now)
            flightPhase += flightBlend.integral(from:from,to:now)
        }
        motionStamp=now;flightAmount=flightBlend.value(at:now)
        backgroundWeights=SIMD4((0..<4).map { Float(backdropBlend[$0].value(at:now)) })
    }
    private var easing: Bool {
        let now=CACurrentMediaTime()
        return !daylightBlend.isSettled(at:now) || !flightBlend.isSettled(at:now) || !backgroundSpeed.isSettled(at:now) || backdropBlend.contains { !$0.isSettled(at:now) } || weatherBlend.contains { !$0.isSettled(at:now) }
    }
    var qaTime: Double?
    var qaOutput: String?
    var qaCaptured = false
    var idleOutput: String?
    var perfOutput: String?
    var perfFrames = 240
    var time: Double { qaTime ?? (elapsed + (running ? CACurrentMediaTime() - origin : 0)) }
    var backgroundTime: Double { qaTime.map { backgroundMotion ? $0 : 0 } ?? backgroundPhase }
    private var sceneTransitionUntil=0.0
    func beginSceneTransition(_ duration: Double) { sceneTransitionUntil=CACurrentMediaTime()+duration }
    var active: Bool { solar.isScrubbing || solar.returningToNow || running || testStart != nil || qaTime != nil || easing || CACurrentMediaTime()<sceneTransitionUntil }

    func togglePlayback() {
        updateMotion();qaTime = nil
        if running { elapsed = time; running = false }
        else { origin = CACurrentMediaTime(); running = true }
        testStart = nil
    }
    func stop() { qaTime = nil; running = false; elapsed = 0; testStart = nil; focus = false; flightPhase = 0; backgroundPhase = 0;motionStamp = CACurrentMediaTime() }
    func select(_ aircraft: Aircraft) { qaTime = nil; settings.aircraft = aircraft
        let saved=UserDefaults.standard.string(forKey:"livery-"+aircraft.rawValue) ?? "CCA"
        livery=Livery.matching(saved,aircraft:aircraft) ?? Livery.defaultLivery(for:aircraft)
        liveryError=nil;settings.geometry=sceneGeometry;cameraDistance=viewPreset == .orbit ? orbitDistance : 76
        elapsed = 0; origin = CACurrentMediaTime(); flightPhase = 0; backgroundPhase = 0;motionStamp = CACurrentMediaTime() }
    func testFlash() { qaTime = nil; testStart = CACurrentMediaTime() }
    func frameLamps() -> [Lamp] {
        var s = settings
        var t = time
        if let start = testStart {
            t = CACurrentMediaTime() - start
            if t >= 60 / s.cyclesPerMinute {
                testStart = nil
                t = time
                if !running { s.strobes = false; s.beacons = false }
            }
        } else if !running && qaTime == nil {
            s.strobes = false; s.beacons = false
        }
        return Lighting.lamps(at: t, settings: s)
    }
    func setView(_ preset: ViewPreset) {
        viewPreset = preset
        switch preset {
        case .orbit: cameraYaw = -0.65; cameraPitch = 0.38
        case .top: cameraYaw = Double.pi; cameraPitch = Double.pi/2-0.00001
        case .bottom: cameraYaw = 0; cameraPitch = -Double.pi/2+0.00001
        case .front: cameraYaw = 0; cameraPitch = 0
        case .left: cameraYaw = -Double.pi/2; cameraPitch = 0
        case .right: cameraYaw = Double.pi/2; cameraPitch = 0
        case .rear: cameraYaw = Double.pi; cameraPitch = 0
        }
        cameraDistance = preset == .orbit ? orbitDistance : 76
    }
    func updateDisplay(_ screen: NSScreen?) {
        guard let screen else { return }
        let h = screen.maximumExtendedDynamicRangeColorComponentValue
        let p = screen.maximumPotentialExtendedDynamicRangeColorComponentValue
        if abs(headroom-h) > 0.01 { headroom = h }
        if abs(potential-p) > 0.01 { potential = p }
        if displayName != screen.localizedName { displayName = screen.localizedName }
    }
    var peak: Double { Lighting.peak(headroom: headroom, hdr: hdr, strength: strength) }
}

 enum ViewPreset: String, CaseIterable, Identifiable {
    case orbit, top, bottom, front, left, right, rear
    var id: String { rawValue }
    var title: String {
        switch self {
        case .orbit: return "自由视角"
        case .top: return "俯视"
        case .bottom: return "仰视"
        case .front: return "正前方"
        case .left: return "左侧"
        case .right: return "右侧"
        case .rear: return "正后方"
        }
    }
}


enum SkyEnvironment: String, CaseIterable, Identifiable {
    case night, dusk, day
    var id: String { rawValue }
    var index: Float { self == .night ? 0 : (self == .dusk ? 1 : 2) }
    var title: String { self == .night ? "夜晚" : (self == .dusk ? "黄昏" : "白天") }
}
enum Backdrop: String, CaseIterable, Identifiable {
    case clouds, flow, stars, studio
    var id: String { rawValue }
    var index: Float { Float(Self.allCases.firstIndex(of:self)!) }
    var symbol: String { switch self { case .clouds:return "cloud";case .flow:return "wind";case .stars:return "sparkles";case .studio:return "square.dashed" } }
    var title: String {
        switch self { case .clouds:return "云层";case .flow:return "气流";case .stars:return "星空";case .studio:return "摄影棚" }
    }
}
enum RenderQuality: String, CaseIterable, Identifiable {
    case efficient, balanced, smooth, ultra
    var id: String { rawValue }
    var fps: Int { self == .efficient ? 30 : (self == .smooth ? 120 : 60) }
    var renderScale: Double { self == .ultra ? 2 : 1 }
    var samples: Int { self == .efficient ? 2 : 4 }
    var title: String { self == .efficient ? "节能 · 30 帧" : (self == .balanced ? "标准 · 60 帧" : (self == .smooth ? "流畅 · 120 帧" : "高精度 · 60 帧")) }
}

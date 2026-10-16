import Foundation
import simd

public enum Aircraft: String, CaseIterable, Identifiable, Sendable {
    case airbus, boeing, b77w, b788, b789, b78x, a332, a333, a359
    public var id: String { rawValue }
    public var title: String { maker.capitalized + " " + modelName }
    public var modelName: String {
        switch self {
        case .airbus: "A320"
        case .boeing: "737-800"
        case .b77w: "777-300ER"
        case .b788: "787-8"
        case .b789: "787-9"
        case .b78x: "787-10"
        case .a332: "A330-200"
        case .a333: "A330-300"
        case .a359: "A350-900"
        }
    }
    public var shortName: String { self == .airbus ? "A320" : self == .boeing ? "B738" : rawValue.uppercased() }
    public var maker: String { [.airbus,.a332,.a333,.a359].contains(self) ? "AIRBUS" : "BOEING" }
    public var isWidebody: Bool { self != .airbus && self != .boeing }
    public var family: String {
        switch self {
        case .airbus: "A320"
        case .boeing: "737"
        case .b77w: "777"
        case .b788,.b789,.b78x: "787"
        case .a332,.a333: "A330"
        case .a359: "A350"
        }
    }
    public var defaultAsset: String {
        switch self {
        case .airbus,.boeing: rawValue
        case .b77w: "b77w-ge90"
        case .b788,.b789,.b78x: rawValue+"-genx"
        case .a332,.a333: rawValue+"-rr"
        case .a359: "a359-xwb"
        }
    }
    public var geometry: AircraftGeometry { AircraftGeometry.catalog[defaultAsset]! }
    public var length: Double { geometry.length }
    public var span: Double { geometry.span }
    public var bodyWidth: Double { geometry.bodyWidth }
    public var tailSpan: Double { geometry.tailSpan }
    public var patternDescription: String {
        if self == .airbus { return "Collins LED · 翼尖双闪 / 尾部单闪" }
        if self == .a332 || self == .a333 { return "翼尖双闪 / 尾部单闪；脉宽与间隔为模拟值" }
        if self == .a359 { return "LED 双闪示意；精确时序尚未核实" }
        return "单闪示意；精确脉宽与相位尚未核实"
    }
    public static func parse(_ value: String) -> Aircraft? {
        let q=value.lowercased()
        if q=="77w" { return .b77w }
        if q=="a320" { return .airbus }
        if q=="b738" || q=="738" { return .boeing }
        return allCases.first { $0.rawValue==q || $0.modelName.lowercased()==q }
    }
}
public struct AircraftGeometry: Codable, Sendable {
    public let id: String
    public let length: Double
    public let span: Double
    public let bodyWidth: Double
    public let tailSpan: Double
    public let engineXY: [Double]
    public let bodyCenterY: Double
    public let finHeight: Double
    public let lights: [String:[Double]]
    public func point(_ key: String) -> SIMD3<Double> {
        let p=lights[key] ?? [0,0,0];return SIMD3(p[0],p[1],p[2])
    }
    public static let catalog: [String:AircraftGeometry] = {
        guard let url=Bundle.module.url(forResource:"Aircraft",withExtension:"json"),let data=try? Data(contentsOf:url),let items=try? JSONDecoder().decode([AircraftGeometry].self,from:data) else { return [:] }
        return Dictionary(uniqueKeysWithValues:items.map { ($0.id,$0) })
    }()
}
public enum LampKind: String { case strobe, beacon, navigation, landing, taxi, logo }
public enum Emission: String {
    case portNavigation, starboardNavigation, tailNavigation
    case portStrobe, starboardStrobe, tailStrobe
    case upperBeacon, lowerBeacon, forwardSpot, logoPort, logoStarboard
}
/// Aircraft coordinates: x starboard, y up, z aft. One unit = one metre.
public struct Lamp {
    public let id: String
    public let position: SIMD3<Double>
    public var x: Double { position.x }
    public let kind: LampKind
    public let rgb: SIMD3<Float>
    public let intensity: Double
    public let radius: Double
    public let emission: Emission
    public init(_ id: String, _ position: SIMD3<Double>, _ kind: LampKind, _ rgb: SIMD3<Float>, _ intensity: Double, _ radius: Double, _ emission: Emission) {
        self.id = id; self.position = position; self.kind = kind; self.rgb = rgb
        self.intensity = intensity; self.radius = radius; self.emission = emission
    }
}
public struct LightSettings {
    public var aircraft: Aircraft = .airbus
    public var geometry: AircraftGeometry?
    public var strobes = true
    public var beacons = true
    public var navigation = true
    public var landing = false
    public var logo = true
    // Collins master beacon 8ES455967: 55 ± 5/min; the white slave lamps accept 60 ± 5/min.
    public var cyclesPerMinute: Double { aircraft == .airbus ? 55 : 60 }
    public var doubleGap: Double { 0.110 }
    public var wingStarts: [Double] { aircraft.maker == "AIRBUS" ? [0,doubleGap] : [0] }
    public var pulseWidth: Double { aircraft == .airbus ? 0.050 : 0.055 }
    public var tailWidth: Double { aircraft == .airbus ? 0.110 : 0.055 }
    public var beaconWidth: Double { aircraft == .airbus ? 0.200 : 0.120 }
    public var beaconOffset: Double { 0.5 }
    public init() {}
}
public enum Lighting {
    public static func phase(_ time: Double, period: Double) -> Double {
        guard time.isFinite, period.isFinite, period > 0 else { return 0 }
        let p = time.truncatingRemainder(dividingBy: period)
        return p < 0 ? p + period : p
    }
    /// LED rectangular pulse. No persistence, minimum-visible-frame hold or time stretching.
    public static func pulse(_ time: Double, starts: [Double], width: Double, period: Double) -> Double {
        guard width > 0, period > 0 else { return 0 }
        return starts.contains { phase(time - $0, period: period) < width } ? 1 : 0
    }
    public static func lamps(at time: Double, settings s: LightSettings) -> [Lamp] {
        let a = s.aircraft, period = 60/s.cyclesPerMinute
        let geometry=s.geometry ?? a.geometry
        let wing = s.strobes ? pulse(time,starts:s.wingStarts,width:s.pulseWidth,period:period) : 0
        let tail = s.strobes ? pulse(time,starts:[0],width:s.tailWidth,period:period) : 0
        let beacon = s.beacons ? pulse(time,starts:[s.beaconOffset*period],width:s.beaconWidth,period:period) : 0
        let white = SIMD3<Float>(1,1,1)
        var result = [Lamp]()
        for side in [-1.0,1.0] {
            let left = side < 0, prefix = left ? "left" : "right"
            // Surface offsets are only centimetres, preventing self-occlusion of a flush lens.
            var nav=geometry.point("nav");nav.x=side*abs(nav.x)
            var strobe=geometry.point("strobe");strobe.x=side*abs(strobe.x)
            result.append(Lamp(prefix+"-strobe",strobe,.strobe,white,wing,1,left ? .portStrobe : .starboardStrobe))
            result.append(Lamp(prefix+"-nav",nav,.navigation,left ? SIMD3(1,0.01,0.018) : SIMD3(0.008,1,0.065),s.navigation ? 0.85 : 0,0.44,left ? .portNavigation : .starboardNavigation))
            if geometry.lights["wingRear"] != nil {
                var aft=geometry.point("wingRear");aft.x=side*abs(aft.x)
                result.append(Lamp(prefix+"-rear-nav",aft,.navigation,white,s.navigation ? 0.60 : 0,0.40,.tailNavigation))
            }
            var landing=geometry.point("landing");landing.x=side*abs(landing.x)
            result.append(Lamp(prefix+"-landing",landing,.landing,SIMD3(1,0.94,0.83),s.landing ? 1 : 0,0.8,.forwardSpot))
            var logo=geometry.point("logo");logo.x=side*abs(logo.x)
            result.append(Lamp(prefix+"-logo",logo,.logo,SIMD3(1,0.94,0.83),s.logo ? 0.35 : 0,0.35,left ? .logoPort : .logoStarboard))
        }
        let rear=geometry.point("tail")
        if a.family == "787" {
            for side in [-1.0,1.0] {
                let prefix=side<0 ? "tail-left" : "tail-right"
                var position=rear;position.x=side*abs(rear.x)
                result.append(Lamp(prefix+"-strobe",position,.strobe,white,tail,1,.tailStrobe))
                var navigation=geometry.point("tailNav");navigation.x=side*abs(navigation.x)
                result.append(Lamp(prefix+"-nav",navigation,.navigation,white,s.navigation ? 0.6 : 0,0.40,.tailNavigation))
            }
        } else {
            result.append(Lamp("tail-strobe",SIMD3(-0.05,rear.y,rear.z),.strobe,white,tail,1,.tailStrobe))
            result.append(Lamp("tail-nav",SIMD3(0.05,rear.y,rear.z),.navigation,white,s.navigation ? 0.6 : 0,0.40,.tailNavigation))
        }
        result.append(Lamp("upper-beacon",geometry.point("upper"),.beacon,SIMD3(1,0.008,0.012),beacon,0.85,.upperBeacon))
        result.append(Lamp("lower-beacon",geometry.point("lower"),.beacon,SIMD3(1,0.008,0.012),beacon,0.85,.lowerBeacon))
        return result
    }
    private static func smooth(_ a: Double,_ b: Double,_ x: Double) -> Double {
        let t = min(1,max(0,(x-a)/(b-a)));return t*t*(3-2*t)
    }
    /// Angular visibility. Navigation sectors follow 14 CFR 25.1387. Other lobes
    /// are plausible analytic optics, not measured IES/candela distributions.
    public static func angularGain(_ emission: Emission, toward direction: SIMD3<Double>) -> Double {
        guard simd_length_squared(direction) > 1e-12 else { return 0 }
        let d = simd_normalize(direction)
        let azimuth = atan2(d.x,-d.z)*180/Double.pi
        let elevation = asin(min(1,max(-1,d.y)))*180/Double.pi
        func sector(_ center: Double,_ half: Double,_ feather: Double = 2) -> Double {
            let difference = abs(phase(azimuth-center+180,period:360)-180)
            return 1-smooth(half,half+feather,difference)
        }
        let navVertical = 0.05+0.95*pow(cos(elevation*Double.pi/180),2)
        let strobeVertical = 1-smooth(75,90,abs(elevation))
        switch emission {
        case .portNavigation: return sector(-55,55)*navVertical
        case .starboardNavigation: return sector(55,55)*navVertical
        case .tailNavigation: return sector(180,70)*navVertical
        case .portStrobe: return sector(-60,100,6)*strobeVertical
        case .starboardStrobe: return sector(60,100,6)*strobeVertical
        case .tailStrobe: return sector(180,60,5)*strobeVertical
        case .upperBeacon: return smooth(-0.02,0.02,d.y)*(0.25+0.75*pow(cos(elevation*Double.pi/180),2))
        case .lowerBeacon: return (1-smooth(-0.02,0.02,d.y))*(0.25+0.75*pow(cos(elevation*Double.pi/180),2))
        case .forwardSpot:
            let axis = simd_normalize(SIMD3<Double>(0,-0.07,-1))
            return smooth(cos(16*Double.pi/180),cos(4*Double.pi/180),simd_dot(d,axis))
        case .logoPort, .logoStarboard:
            let axis = simd_normalize(SIMD3<Double>(emission == .logoPort ? 0.55 : -0.55,1,0.35))
            return smooth(cos(30*Double.pi/180),cos(12*Double.pi/180),simd_dot(d,axis))
        }
    }
    public static func peak(headroom: Double,hdr: Bool,strength: Double) -> Double {
        max(0.1,min(1,strength))*(hdr ? max(1,headroom.isFinite ? headroom : 1) : 1)
    }
}

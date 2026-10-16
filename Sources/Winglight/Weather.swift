import Foundation

enum SceneWeather: String,CaseIterable,Identifiable {
    case clear,cloudy,rain,fog,storm
    var id: String { rawValue }
    var title: String { switch self { case .clear:return "晴朗";case .cloudy:return "多云";case .rain:return "雨";case .fog:return "雾";case .storm:return "雷雨" } }
    var symbol: String { switch self { case .clear:return "sun.max";case .cloudy:return "cloud";case .rain:return "cloud.rain";case .fog:return "cloud.fog";case .storm:return "cloud.bolt.rain" } }
    // Cloud coverage, precipitation, extinction, distant lightning.
    var parameters: SIMD4<Double> {
        switch self {
        case .clear:return SIMD4(0.10,0,0,0)
        case .cloudy:return SIMD4(0.85,0,0.08,0)
        case .rain:return SIMD4(0.95,0.65,0.22,0)
        case .fog:return SIMD4(0.75,0,0.85,0)
        case .storm:return SIMD4(1,1,0.34,1)
        }
    }
}

/// Sparse weather flashes, independent of every aircraft lamp's time function.
enum StormLighting {
    static func sample(time: Double,strength: Float,headroom: Double,hdr: Bool,reduceMotion: Bool) -> SIMD4<Float> {
        let period=11.7,cycle=floor(max(0,time)/period),phase=max(0,time)-cycle*period
        // Stable within one flash; event timing varies between weather cycles.
        func random(_ salt: Double) -> Double {
            let x=sin(cycle*127.1+salt*311.7)*43758.5453
            return x-floor(x)
        }
        let start=3.2+(cycle == 0 ? 0 : (random(1)-0.5)*1.4)
        func pulse(_ start: Double,_ duration: Double) -> Double {
            guard phase>=start && phase<start+duration else { return 0 }
            let elapsed=phase-start,t=elapsed/duration
            let tail=max(0,min(1,(1-t)/0.30))
            return min(1,elapsed/0.0015)*exp(-elapsed/0.05)*tail*tail*(3-2*tail)
        }
        let initial=pulse(start,0.050)
        let returns=pulse(start+0.105+random(2)*0.025,0.038)*0.78
            + pulse(start+0.205+random(3)*0.035,0.032)*(0.38+random(4)*0.22)
        let amplitude=reduceMotion ? 0 : (initial+returns)*Double(max(0,min(1,strength)))
        // Subsequent return strokes reuse the channel, with much fainter branches.
        return SIMD4(Float(amplitude),Float(hdr ? max(1,min(headroom,12)) : 1),Float(cycle),initial>0 ? 1 : 0.10)
    }
}

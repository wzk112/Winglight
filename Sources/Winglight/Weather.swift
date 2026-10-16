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
        func pulse(_ start: Double,_ duration: Double) -> Double {
            guard phase>=start && phase<start+duration else { return 0 }
            let t=(phase-start)/duration
            return min(1,t/0.08)*pow(1-t,0.55)
        }
        let amplitude=reduceMotion ? 0 : (pulse(3.2,0.085)+pulse(3.37,0.13)*0.82)*Double(strength)
        return SIMD4(Float(amplitude),Float(hdr ? max(1,min(headroom,12)) : 1),Float(cycle),0)
    }
}

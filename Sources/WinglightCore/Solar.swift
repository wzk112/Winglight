import Foundation
import simd

/// Geometric solar position using the NOAA/Meeus equations. Sunrise and sunset
/// use a -0.833° solar-centre altitude (standard refraction and solar radius).
public enum Solar {
    public struct Position {
        public let elevation: Double
        public let azimuth: Double
        public var direction: SIMD3<Float> {
            let e=elevation * .pi/180,a=azimuth * .pi/180
            // North is the nose (-z), east is +x, up is +y.
            return SIMD3(Float(sin(a)*cos(e)),Float(sin(e)),Float(-cos(a)*cos(e)))
        }
        public var environment: Float {
            let t=min(1,max(0,(elevation+12)/22));return Float(2*t*t*(3-2*t))
        }
    }
    public struct Events { public let sunrise: Date?;public let sunset: Date?;public let polarDay: Bool }
    public static func position(at date: Date,latitude: Double,longitude: Double) -> Position {
        let r=Double.pi/180
        let jd=date.timeIntervalSince1970/86400+2440587.5,t=(jd-2451545)/36525
        let l=Lighting.phase(280.46646+t*(36000.76983+t*0.0003032),period:360)
        let m=357.52911+t*(35999.05029-0.0001537*t),e=0.016708634-t*(0.000042037+0.0000001267*t)
        let c=sin(m*r)*(1.914602-t*(0.004817+0.000014*t))+sin(2*m*r)*(0.019993-0.000101*t)+sin(3*m*r)*0.000289
        let omega=125.04-1934.136*t,lambda=(l+c-0.00569-0.00478*sin(omega*r))*r
        let ob=(23+(26+(21.448-t*(46.815+t*(0.00059-t*0.001813)))/60)/60+0.00256*cos(omega*r))*r
        let decl=asin(sin(ob)*sin(lambda)),y=pow(tan(ob/2),2)
        let equation=4/r*(y*sin(2*l*r)-2*e*sin(m*r)+4*e*y*sin(m*r)*cos(2*l*r)-0.5*y*y*sin(4*l*r)-1.25*e*e*sin(2*m*r))
        let utcMinutes=Lighting.phase(date.timeIntervalSince1970,period:86400)/60
        let hour=(Lighting.phase(utcMinutes+equation+4*longitude,period:1440)/4-180)*r
        let lat=min(89.999,max(-89.999,latitude))*r
        let cosine=sin(lat)*sin(decl)+cos(lat)*cos(decl)*cos(hour)
        let altitude=asin(min(1,max(-1,cosine)))/r
        let azimuth=Lighting.phase(atan2(sin(hour),cos(hour)*sin(lat)-tan(decl)*cos(lat))/r+180,period:360)
        return Position(elevation:altitude,azimuth:azimuth)
    }
    public static func events(on date: Date,latitude: Double,longitude: Double,timeZone: TimeZone) -> Events {
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=timeZone
        let start=calendar.startOfDay(for:date),end=calendar.date(byAdding:.day,value:1,to:start)!
        func altitude(_ d: Date) -> Double { position(at:d,latitude:latitude,longitude:longitude).elevation+0.833 }
        var sunrise: Date?,sunset: Date?,previous=start,old=altitude(start)
        while previous<end {
            let next=min(end,previous.addingTimeInterval(300)),value=altitude(next)
            if (old<0 && value>=0)||(old>=0 && value<0) {
                var low=previous,high=next
                for _ in 0..<20 {
                    let mid=low.addingTimeInterval(high.timeIntervalSince(low)/2)
                    if (altitude(mid)>=0)==(old>=0) { low=mid } else { high=mid }
                }
                let event=low.addingTimeInterval(high.timeIntervalSince(low)/2)
                if value>old { sunrise=event } else { sunset=event }
            }
            previous=next;old=value
        }
        return Events(sunrise:sunrise,sunset:sunset,polarDay:sunrise==nil && sunset==nil && altitude(start)>0)
    }
}

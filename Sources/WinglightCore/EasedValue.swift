import Foundation

/// Smooth endpoint transitions with an exact integral for continuous phase.
public struct EasedValue {
    public private(set) var target: Double
    private var source: Double
    private var start: Double = 0
    private var duration: Double = 0
    public init(_ value: Double) { source=value;target=value }
    public func value(at time: Double) -> Double {
        guard duration>0 else { return target }
        let x=min(1,max(0,(time-start)/duration))
        return source+(target-source)*x*x*(3-2*x)
    }
    public mutating func set(_ value: Double,at time: Double,duration: Double = 0.8) {
        source=self.value(at:time);target=value;start=time;self.duration=max(0,duration)
    }
    public func isSettled(at time: Double) -> Bool { time>=start+duration }
    private func primitive(_ time: Double) -> Double {
        let t=time-start
        guard duration>0 else { return target*t }
        if t<=0 { return source*t }
        if t>=duration { return (source+target)*duration/2+target*(t-duration) }
        let x=t/duration
        return source*t+(target-source)*duration*(x*x*x-x*x*x*x/2)
    }
    public func integral(from: Double,to: Double) -> Double { primitive(to)-primitive(from) }
}

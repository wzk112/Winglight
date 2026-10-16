import XCTest
import simd
@testable import WinglightCore

final class LightingTests: XCTestCase {
    func intensity(_ id: String,_ time: Double,_ aircraft: Aircraft = .airbus) -> Double {
        var s = LightSettings();s.aircraft = aircraft
        return Lighting.lamps(at:time,settings:s).first{$0.id == id}!.intensity
    }
    func direction(_ azimuth: Double,_ elevation: Double = 0) -> SIMD3<Double> {
        let a = azimuth * .pi/180,e = elevation * .pi/180
        return SIMD3(sin(a)*cos(e),sin(e),-cos(a)*cos(e))
    }
    func testCollinsLEDPulseWidthsAndDarkGapAreNotStretched() {
        for t in [0.0001,0.025,0.0499,0.1101,0.135,0.1599] { XCTAssertEqual(intensity("left-strobe",t),1) }
        for t in [0.0501,0.08,0.1099,0.1601,0.3] { XCTAssertEqual(intensity("left-strobe",t),0) }
        XCTAssertEqual(intensity("tail-strobe",0.1099),1)
        XCTAssertEqual(intensity("tail-strobe",0.1101),0)
        // Count the ON samples over one complete 55/min cycle at 100 kHz.
        let samples = (0..<109091).filter { intensity("left-strobe",Double($0)/100000) == 1 }.count
        XCTAssertEqual(samples,10001,accuracy:2)
    }
    func testBothWingLightsSynchronizeAndTailOnlyFlashesOnce() {
        for frame in 0..<1100 {
            let t = Double(frame)/1000
            XCTAssertEqual(intensity("left-strobe",t),intensity("right-strobe",t))
        }
        XCTAssertEqual(intensity("tail-strobe",0.135),0)
    }
    func testBoeingSingleFlashIsFixedAndSeparateFromAirbusPreset() {
        XCTAssertEqual(intensity("left-strobe",0.03,.boeing),1)
        XCTAssertEqual(intensity("left-strobe",0.056,.boeing),0)
        XCTAssertEqual(intensity("left-strobe",0.13,.boeing),0)
        XCTAssertEqual(intensity("left-strobe",1.03,.boeing),1)
    }
    func testUpperAndLowerBeaconSamePulseButDifferentDirections() {
        let s = LightSettings(), start = 0.5*60/55
        XCTAssertEqual(intensity("upper-beacon",start+0.01),1)
        XCTAssertEqual(intensity("lower-beacon",start+0.199),1)
        XCTAssertEqual(intensity("lower-beacon",start+0.201),0)
        XCTAssertEqual(Lighting.lamps(at:0,settings:s).filter{$0.kind == .beacon}.count,2)
        XCTAssertEqual(Lighting.angularGain(.upperBeacon,toward:direction(0,-30)),0)
        XCTAssertEqual(Lighting.angularGain(.lowerBeacon,toward:direction(0,30)),0)
        XCTAssertGreaterThan(Lighting.angularGain(.lowerBeacon,toward:direction(0,-30)),0)
    }
    func testNavigation110DegreeSectorsAnd140DegreeTail() {
        XCTAssertGreaterThan(Lighting.angularGain(.portNavigation,toward:direction(-109)),0.99)
        XCTAssertEqual(Lighting.angularGain(.portNavigation,toward:direction(-113)),0)
        XCTAssertEqual(Lighting.angularGain(.portNavigation,toward:direction(20)),0)
        XCTAssertGreaterThan(Lighting.angularGain(.starboardNavigation,toward:direction(109)),0.99)
        XCTAssertEqual(Lighting.angularGain(.starboardNavigation,toward:direction(-20)),0)
        XCTAssertGreaterThan(Lighting.angularGain(.tailNavigation,toward:direction(111)),0.99)
        XCTAssertGreaterThan(Lighting.angularGain(.tailNavigation,toward:direction(-111)),0.99)
        XCTAssertEqual(Lighting.angularGain(.tailNavigation,toward:direction(0)),0)
        XCTAssertEqual(Lighting.angularGain(.portNavigation,toward:direction(180)),0)
        XCTAssertEqual(Lighting.angularGain(.starboardNavigation,toward:direction(180)),0)
    }
    func testLandingLightsAreForwardBeamsRatherThanOmnidirectionalDots() {
        XCTAssertGreaterThan(Lighting.angularGain(.forwardSpot,toward:direction(0,-4)),0.99)
        for a in [30.0,90,180,-90] { XCTAssertEqual(Lighting.angularGain(.forwardSpot,toward:direction(a)),0) }
    }
    func testViewAngleDoesNotChangePulseTiming() {
        for t in [0.025,0.08,0.135,0.2] {
            let s = LightSettings(), lamps = Lighting.lamps(at:t,settings:s)
            let before = lamps.map(\.intensity)
            for az in stride(from:-180.0,through:180,by:10) {
                for lamp in lamps { _ = Lighting.angularGain(lamp.emission,toward:direction(az,25)) }
            }
            XCTAssertEqual(before,Lighting.lamps(at:t,settings:s).map(\.intensity))
        }
    }
    func testSwitchesExtinguishEntireGroups() {
        var s = LightSettings();s.strobes = false;s.beacons = false;s.navigation = false;s.logo = false
        for t in [0.0,0.13,0.6] { XCTAssertTrue(Lighting.lamps(at:t,settings:s).allSatisfy{$0.intensity == 0}) }
    }
    func testWidebodyLightConfigurationAndNonStretchedGaps() {
        for aircraft in Aircraft.allCases {
            var s=LightSettings();s.aircraft=aircraft
            let lamps=Lighting.lamps(at:0.01,settings:s)
            XCTAssertEqual(Set(lamps.map(\.id)).count,lamps.count)
            XCTAssertEqual(lamps.filter { $0.kind == .strobe }.count,aircraft.family == "787" ? 4 : 3)
            XCTAssertEqual(lamps.filter { $0.kind == .beacon }.count,2)
            XCTAssertEqual(intensity("left-strobe",0.08,aircraft),0)
            XCTAssertEqual(intensity("left-strobe",0.135,aircraft),aircraft.maker == "AIRBUS" ? 1 : 0)
        }
        for aircraft in [Aircraft.b788,.b789,.b78x] {
            var s=LightSettings();s.aircraft=aircraft
            let tail=Lighting.lamps(at:0.01,settings:s).filter { $0.id.hasPrefix("tail-") && $0.kind == .strobe }
            XCTAssertEqual(tail[0].position.x,-tail[1].position.x,accuracy:0.001)
            XCTAssertGreaterThan(abs(tail[0].position.x),0.4)
        }
    }
    func testEDRUsesOnlyCurrentHeadroomAndSDRFallback() {
        XCTAssertEqual(Lighting.peak(headroom:4,hdr:true,strength:1),4)
        XCTAssertEqual(Lighting.peak(headroom:4,hdr:false,strength:1),1)
        XCTAssertEqual(Lighting.peak(headroom:1,hdr:true,strength:1),1)
        XCTAssertEqual(Lighting.peak(headroom:4,hdr:true,strength:0.5),2)
        XCTAssertEqual(Lighting.peak(headroom:.nan,hdr:true,strength:1),1)
    }
    func testLongRunningClockIsPeriodic() {
        XCTAssertEqual(Lighting.pulse(86400.01,starts:[0],width:0.05,period:1),1)
        XCTAssertEqual(Lighting.phase(-0.2,period:1),0.8,accuracy:1e-10)
        XCTAssertEqual(Lighting.pulse(10,starts:[0],width:0,period:1),0)
    }
}

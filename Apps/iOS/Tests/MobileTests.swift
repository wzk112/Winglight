import XCTest
import CoreLocation
import MetalKit
import WinglightCore
@testable import Winglight

final class MobileTests: XCTestCase {
    @MainActor func testEveryAircraftRendersWithSharedMetalPipelinesAndReleasesOldResources() async throws {
        let device=try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let solar=SolarController(manager:CLLocationManager(),preferences:UserDefaults(suiteName:"Winglight.MobileTests")!,automatic:false)
        let state=AppState(solar:solar);state.solar.followsClock=false;state.quality = .efficient;state.qaTime=0.015
        let view=OrbitView(frame:CGRect(x:0,y:0,width:390,height:600),device:device)
        view.appState=state;view.colorPixelFormat = .rgba16Float;view.drawableSize=CGSize(width:390,height:600)
        let renderer=Renderer(state:state);renderer.configure(view)
        XCTAssertNil(state.rendererError)
        let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:390,height:600,mipmapped:false)
        d.usage=[.renderTarget,.shaderRead]
        let target=try XCTUnwrap(device.makeTexture(descriptor:d))
        let selections=Aircraft.allCases.flatMap { aircraft in
            Dictionary(grouping:Livery.available(for:aircraft),by:{$0.asset(for:aircraft)}).keys.sorted().map { asset in
                (aircraft,Livery.available(for:aircraft).first { $0.asset(for:aircraft)==asset }!)
            }
        }
        XCTAssertEqual(selections.count,17)
        for (aircraft,livery) in selections {
            state.select(aircraft);state.chooseLivery(livery);state.qaTime=0.015;renderer.updateLivery(view)
            let deadline=Date().addingTimeInterval(120)
            while (renderer.loadedAsset != state.assetID || state.liveryLoading) && Date()<deadline { try await Task.sleep(for:.milliseconds(50)) }
            XCTAssertFalse(state.liveryLoading,"\(aircraft): timed out")
            XCTAssertNil(state.liveryError,"\(aircraft)")
            for background in Backdrop.allCases {
                state.backdrop=background;state.weather = .storm;state.updateMotion()
                let command=try XCTUnwrap(renderer.draw(in:view,destination:target),"\(aircraft) / \(background)")
                await command.completed();XCTAssertNil(command.error)
            }
            renderer.releaseInactiveResources()
            XCTAssertEqual(renderer.models.count,1);XCTAssertEqual(renderer.flows.count,1)
        }
    }
    @MainActor func testPortraitProjectionFitsAircraftAndLifecyclePauses() throws {
        let state=AppState(solar:SolarController(manager:CLLocationManager(),preferences:UserDefaults(suiteName:"Winglight.MobileProjection")!,automatic:false))
        let renderer=Renderer(state:state)
        for aircraft in Aircraft.allCases {
            state.select(aircraft);state.flightMotion=false
            for preset in ViewPreset.allCases {
                state.setView(preset)
                let (projection,_,_)=renderer.camera(aspect:390.0/844)
                for point in [SIMD3<Float>(Float(aircraft.span/2),0,0),SIMD3<Float>(Float(-aircraft.span/2),0,0),SIMD3<Float>(0,0,Float(aircraft.length/2)),SIMD3<Float>(0,0,Float(-aircraft.length/2))] {
                    let clip=projection*SIMD4(point,1)
                    XCTAssertLessThan(abs(clip.x/clip.w),1,"\(aircraft) / \(preset)")
                    XCTAssertLessThan(abs(clip.y/clip.w),1,"\(aircraft) / \(preset)")
                }
            }
        }
        let view=OrbitView(frame:CGRect(x:0,y:0,width:390,height:844),device:MTLCreateSystemDefaultDevice())
        view.appState=state;state.togglePlayback();view.scheduleRendering()
        XCTAssertTrue(view.isPaused,"A detached/background scene must stop its display link")
    }
}

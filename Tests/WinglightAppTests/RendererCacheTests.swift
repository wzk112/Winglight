import XCTest
import CoreLocation
import MetalKit
import WinglightCore
@testable import Winglight

final class RendererCacheTests: XCTestCase {
    @MainActor func testReturningToRecentAircraftReusesPreparedGeometryAndLatestSelectionWins() async throws {
        let device=try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let solar=SolarController(manager:CLLocationManager(),preferences:UserDefaults(suiteName:"Winglight.CacheTests")!,automatic:false)
        let state=AppState(solar:solar);state.solar.followsClock=false
        let view=OrbitView(frame:NSRect(x:0,y:0,width:640,height:400),device:device)
        view.appState=state;view.colorPixelFormat = .rgba16Float
        let renderer=Renderer(state:state);renderer.configure(view)
        func loaded(_ asset: String) async throws {
            for _ in 0..<1200 {
                try await Task.sleep(nanoseconds:50_000_000)
                if renderer.models[asset] != nil && !state.liveryLoading { return }
                if let error=state.liveryError ?? state.rendererError { XCTFail(error);return }
            }
            XCTFail("Timed out loading \(asset)")
        }
        try await loaded(state.assetID)
        let first=try XCTUnwrap(renderer.models[state.assetID]?.0)
        let flow=try XCTUnwrap(renderer.flows[state.assetID]?.0)
        state.select(.boeing);renderer.updateLivery(view);try await loaded(state.assetID)
        state.select(.airbus)
        let start=Date();renderer.updateLivery(view);try await loaded(state.assetID)
        XCTAssertTrue(first === renderer.models[state.assetID]?.0)
        XCTAssertTrue(flow === renderer.flows[state.assetID]?.0)
        print("Warm aircraft return: \(Date().timeIntervalSince(start)*1000) ms")
        // Cancel a large uncached assembly before a newer cached selection.
        state.select(.b788);renderer.updateLivery(view)
        state.select(.boeing);renderer.updateLivery(view);try await loaded(state.assetID)
        XCTAssertEqual(state.assetID,"boeing");XCTAssertNil(state.liveryError)
        XCTAssertLessThanOrEqual(renderer.models.count,2)
        let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:640,height:400,mipmapped:false)
        d.usage=[.renderTarget,.shaderRead]
        view.drawableSize=CGSize(width:640,height:400)
        let target=try XCTUnwrap(device.makeTexture(descriptor:d))
        let command=try XCTUnwrap(renderer.draw(in:view,destination:target))
        command.waitUntilCompleted();XCTAssertNil(command.error)
    }
}

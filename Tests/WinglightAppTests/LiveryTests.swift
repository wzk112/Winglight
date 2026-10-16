import XCTest
import MetalKit
import WinglightCore
@testable import Winglight

final class LiveryTests: XCTestCase {
    func testCatalogAssetsHaveCorrectResolutionAndCanLoadOnGPU() throws {
        let all=Livery.catalog
        XCTAssertEqual(all.count,309)
        XCTAssertEqual(Set(all.map(\.aircraft)).count,Aircraft.allCases.count)
        XCTAssertEqual(Set(all.map(\.id)).count,all.count)
        XCTAssertEqual(Livery.available(for:.airbus).count,50)
        XCTAssertEqual(Livery.available(for:.boeing).count,58)
        let device=try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let loader=MTKTextureLoader(device:device)
        var loaded=Set<URL>()
        for livery in all {
            try autoreleasepool {
                let url=try XCTUnwrap(livery.textureURL,livery.id)
                let texture=try loader.newTexture(URL:url,options:[.SRGB:true,.generateMipmaps:true,.textureStorageMode:MTLStorageMode.private.rawValue])
                XCTAssertEqual(texture.width,livery.resolution,livery.id)
                XCTAssertEqual(texture.height,livery.textureSize?[1] ?? livery.resolution,livery.id)
                XCTAssertGreaterThan(texture.mipmapLevelCount,1,livery.id)
                if let atlases=livery.atlasURLs {
                    XCTAssertNotNil(AircraftGeometry.catalog[livery.asset(for:Aircraft(rawValue:livery.aircraft)!)],livery.id)
                    for atlas in atlases where !loaded.contains(atlas) {
                        let mapped=try loader.newTexture(URL:atlas,options:[.SRGB:true,.generateMipmaps:true,.textureStorageMode:MTLStorageMode.private.rawValue])
                        XCTAssertGreaterThanOrEqual(mapped.width,512,livery.id)
                        XCTAssertGreaterThan(mapped.mipmapLevelCount,1,livery.id)
                        loaded.insert(atlas)
                    }
                }
                if livery.engineTexture != nil {
                    let engine=try loader.newTexture(URL:XCTUnwrap(livery.engineURL),options:[.SRGB:true,.generateMipmaps:true])
                    XCTAssertGreaterThanOrEqual(engine.width,2048,livery.id)
                }
                XCTAssertFalse(livery.english.localizedCaseInsensitiveContains("fictional"),livery.id)
            }
        }
    }
    func testChineseEnglishAndCodeSearchDoesNotCrossAircraft() {
        XCTAssertTrue(Livery.available(for:.a333).contains { $0.matches("南航") })
        XCTAssertTrue(Livery.available(for:.b789).contains { $0.matches("厦航") })
        XCTAssertTrue(Livery.available(for:.b789).contains { $0.code=="CXA" && $0.special == true })
        XCTAssertTrue(Livery.airChina.matches("国航"))
        XCTAssertTrue(Livery.airChina.matches("中国国际"))
        XCTAssertTrue(Livery.airChina.matches("air china"))
        XCTAssertTrue(Livery.airChina.matches("cca"))
        XCTAssertEqual(Livery.matching("QFA",aircraft:.boeing)?.title,"澳洲航空")
        XCTAssertNil(Livery.matching("QFA",aircraft:.airbus))
        XCTAssertEqual(Livery.matching("CCA",aircraft:.boeing)?.aircraft,"boeing")
    }
    @MainActor func testAircraftRemembersItsOwnLiveryAndNeutralSelection() {
        let defaults=UserDefaults.standard,keys=["livery-airbus","livery-boeing"]
        let before=keys.map { defaults.object(forKey:$0) }
        defer { for (key,value) in zip(keys,before) { if let value { defaults.set(value,forKey:key) } else { defaults.removeObject(forKey:key) } } }
        let state=AppState()
        state.select(.airbus);state.chooseLivery(Livery.matching("EZY",aircraft:.airbus)!)
        state.select(.boeing);state.chooseLivery(Livery.matching("QFA",aircraft:.boeing)!)
        state.select(.airbus);XCTAssertEqual(state.livery.code,"EZY")
        state.select(.boeing);XCTAssertEqual(state.livery.code,"QFA")
        state.chooseLivery(.neutral);state.select(.airbus);state.select(.boeing)
        XCTAssertTrue(state.livery.isNeutral)
    }
}

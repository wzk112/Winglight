import AppKit
import CoreLocation
import MetalKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import WinglightCore

/// Fixed full-resolution scenes use the production renderer, with deterministic
/// time/headroom and unquantized RGBA16F captures for before/after comparison.
@MainActor enum PerformanceAudit {
    struct Scene {
        let name: String
        let aircraft: Aircraft
        let background: Backdrop
        let environment: SkyEnvironment
        let weather: SceneWeather
        var time: Double = 0.015
        var quality: RenderQuality = .ultra
        var wireframe = false
    }
    static func run(directory: String,frames: Int,filter: String?) async -> Bool {
        let output=URL(fileURLWithPath:directory,isDirectory:true)
        do {
            try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
            for name in ["results.json","error.txt"] {
                try? FileManager.default.removeItem(at:output.appendingPathComponent(name))
            }
            guard let device=MTLCreateSystemDefaultDevice() else { throw failure("No Metal device") }
            let preferences=UserDefaults(suiteName:"Winglight.PerformanceAudit")!
            let solar=SolarController(manager:CLLocationManager(),preferences:preferences,automatic:false)
            let state=AppState(solar:solar);state.solar.followsClock=false
            let view=OrbitView(frame:NSRect(x:0,y:0,width:1180,height:820),device:device)
            view.appState=state;view.autoResizeDrawable=false;view.drawableSize=CGSize(width:4720,height:3280)
            view.colorPixelFormat = .rgba16Float
            let renderer=Renderer(state:state);renderer.auditHeadroom=6;renderer.configure(view)
            let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:4720,height:3280,mipmapped:false)
            descriptor.storageMode = .shared;descriptor.usage=[.renderTarget,.shaderRead]
            guard let target=device.makeTexture(descriptor:descriptor) else { throw failure("No target texture") }
            let scenes=[
                Scene(name:"a320-clouds-day",aircraft:.airbus,background:.clouds,environment:.day,weather:.clear),
                Scene(name:"a320-clouds-night",aircraft:.airbus,background:.clouds,environment:.night,weather:.clear),
                Scene(name:"a320-flow-day",aircraft:.airbus,background:.flow,environment:.day,weather:.clear),
                Scene(name:"a320-studio-day",aircraft:.airbus,background:.studio,environment:.day,weather:.clear),
                Scene(name:"a320-storm-night",aircraft:.airbus,background:.clouds,environment:.night,weather:.storm,time:3.21),
                Scene(name:"a320-stars",aircraft:.airbus,background:.stars,environment:.night,weather:.clear),
                Scene(name:"a320-wireframe",aircraft:.airbus,background:.studio,environment:.day,weather:.clear,wireframe:true),
                Scene(name:"b777-flow-night",aircraft:.b77w,background:.flow,environment:.night,weather:.rain),
                Scene(name:"a320-2x-msaa",aircraft:.airbus,background:.clouds,environment:.day,weather:.clear,quality:.efficient)
            ]
            var results=[[String:Any]]()
            for scene in scenes where filter == nil || scene.name.contains(filter!) {
                state.select(scene.aircraft);state.livery=Livery.defaultLivery(for:scene.aircraft)
                state.cameraDistance=state.orbitDistance;state.environment=scene.environment
                state.backdrop=scene.background;state.weather=scene.weather;state.quality=scene.quality
                state.wireframe=scene.wireframe;state.qaTime=scene.time
                renderer.updateLivery(view)
                var ticks=0
                while (state.liveryLoading || renderer.models[state.assetID] == nil) && ticks<1200 {
                    try await Task.sleep(nanoseconds:50_000_000);ticks+=1
                }
                if let error=state.rendererError ?? state.liveryError { throw failure(error) }
                guard renderer.models[state.assetID] != nil else { throw failure("Model load timeout") }
                // Warm shadows, textures and shader caches outside the measurement.
                for _ in 0..<12 { _=try render(renderer,view,target) }
                var image=Data(count:target.width*target.height*8)
                image.withUnsafeMutableBytes { target.getBytes($0.baseAddress!,bytesPerRow:target.width*8,from:MTLRegionMake2D(0,0,target.width,target.height),mipmapLevel:0) }
                try image.write(to:output.appendingPathComponent(scene.name+".rgba16f"))
                let context=CIContext(mtlDevice:device)
                let space=CGColorSpace(name:CGColorSpace.extendedLinearSRGB)!
                if let ci=CIImage(mtlTexture:target,options:[.colorSpace:space]),
                   let cg=context.createCGImage(ci.oriented(.downMirrored),from:CGRect(x:0,y:0,width:target.width,height:target.height),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!),
                   let destination=CGImageDestinationCreateWithURL(output.appendingPathComponent(scene.name+".png") as CFURL,UTType.png.identifier as CFString,1,nil) {
                    CGImageDestinationAddImage(destination,cg,nil);CGImageDestinationFinalize(destination)
                }
                var gpu=[Double](),cpu=[Double]()
                for frame in 0..<max(30,frames) {
                    state.qaTime=scene.time+Double(frame)/60
                    let start=CACurrentMediaTime()
                    guard let command=renderer.draw(in:view,destination:target) else { throw failure("No command buffer") }
                    cpu.append((CACurrentMediaTime()-start)*1000)
                    try complete(command)
                    gpu.append((command.gpuEndTime-command.gpuStartTime)*1000)
                }
                func p95(_ x: [Double]) -> Double { x.sorted()[Int(Double(x.count-1)*0.95)] }
                let row: [String:Any] = ["scene":scene.name,"device":device.name,"width":target.width,"height":target.height,"samples":scene.quality.samples,"frames":gpu.count,"headroom":6,"gpuMeanMS":gpu.reduce(0,+)/Double(gpu.count),"gpuP95MS":p95(gpu),"cpuMeanMS":cpu.reduce(0,+)/Double(cpu.count),"cpuP95MS":p95(cpu)]
                results.append(row)
                try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("results.json"))
                print("PERFORMANCE",scene.name,row["gpuMeanMS"]!);fflush(stdout)
            }
            guard !results.isEmpty else { throw failure("No scenes match the filter") }
            return true
        } catch {
            try? String(describing:error).write(to:output.appendingPathComponent("error.txt"),atomically:true,encoding:.utf8)
            print("PERFORMANCE ERROR",error);fflush(stdout)
            return false
        }
    }
    static func failure(_ message: String) -> NSError { NSError(domain:"Winglight.PerformanceAudit",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
    static func complete(_ command: MTLCommandBuffer) throws {
        command.waitUntilCompleted()
        if let error=command.error { throw error }
    }
    static func render(_ renderer: Renderer,_ view: MTKView,_ target: MTLTexture) throws -> MTLCommandBuffer {
        guard let command=renderer.draw(in:view,destination:target) else { throw failure("No command buffer") }
        try complete(command)
        return command
    }
}

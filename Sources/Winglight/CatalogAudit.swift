import AppKit
import MetalKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import WinglightCore

/// Uses the production Metal renderer and actual atlases without opening windows.
@MainActor enum CatalogAudit {
    static func run(directory: String,filter: String?,details: Bool = false) async {
        let out=URL(fileURLWithPath:directory,isDirectory:true)
        try? FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        guard let device=MTLCreateSystemDefaultDevice() else { return }
        let state=AppState();state.environment = .day;state.solar.followsClock=false
        state.auditUnlit=CommandLine.arguments.contains("--audit-unlit")
        state.focus=true;state.quality = .balanced;state.flightMotion=false;state.backgroundMotion=true;state.backdrop = .studio;state.qaTime=0.22
        let args=CommandLine.arguments
        func argument(_ name: String) -> String? { guard let i=args.firstIndex(of:name),args.indices.contains(i+1) else { return nil };return args[i+1] }
        if let value=argument("--environment"),let mode=SkyEnvironment(rawValue:value) { state.environment=mode }
        if let value=argument("--background"),let mode=Backdrop(rawValue:value) { state.backdrop=mode }
        if let value=argument("--weather"),let mode=SceneWeather(rawValue:value) { state.weather=mode }
        if args.contains("--flight-motion") { state.flightMotion=true }
        if args.contains("--no-background-motion") { state.backgroundMotion=false }
        if args.contains("--no-cabin") { state.cabinLights=false }
        let view=OrbitView(frame:NSRect(x:0,y:0,width:960,height:600),device:device)
        view.appState=state;view.colorPixelFormat = .rgba16Float;view.autoResizeDrawable=false;view.drawableSize=CGSize(width:1600,height:1000)
        let renderer=Renderer(state:state);renderer.configure(view)
        let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:1600,height:1000,mipmapped:false)
        d.usage=[.renderTarget,.shaderRead];d.storageMode = .shared
        guard let target=device.makeTexture(descriptor:d) else { return }
        let context=CIContext(mtlDevice:device,options:[.cacheIntermediates:false])
        var records=[[String:Any]]()
        var assets=Set<String>()
        let selected=Livery.catalog.filter { item in
            guard let filter else { return true }
            return filter.split(separator:",").contains { item.id==$0 || item.aircraft==$0 }
        }.filter { item in !details || assets.insert(item.model ?? item.aircraft).inserted }
        for livery in selected {
            guard let aircraft=Aircraft(rawValue:livery.aircraft) else { continue }
            state.select(aircraft);state.livery=livery;state.qaTime=Double(argument("--qa-time") ?? "0.22") ?? 0.22;state.liveryLoading=true
            renderer.updateLivery(view)
            var ticks=0
            while state.liveryLoading && ticks<1200 { try? await Task.sleep(nanoseconds:50_000_000);ticks+=1 }
            var row: [String:Any] = ["id":livery.id,"model":state.assetID,"resolution":livery.resolution,"textureCount":livery.textures?.count ?? 1]
            if let error=state.rendererError ?? state.liveryError { row["error"]=error }
            else if state.liveryLoading { row["error"]="timeout" }
            else {
                var images=[String]()
                let angles=details ? ["cockpit-left","cockpit-right","forward-left","forward-right","mid-left","mid-right","aft-left","aft-right","wing-left","wing-right","belly"] : ["left","right","nose","tail"]
                for angle in angles {
                    state.auditCameraTarget=nil
                    if details {
                        let side: Double=angle.hasSuffix("left") ? -1 : 1
                        let length=aircraft.length,width=aircraft.bodyWidth
                        state.setView(.orbit);state.cameraYaw=side * .pi/2;state.cameraPitch=0.08;state.cameraDistance=width*3.3
                        var target=SIMD3<Float>(0,0.5,0)
                        if angle.hasPrefix("cockpit") { target=SIMD3(0,0.7,Float(-length*0.43));state.cameraYaw=side*0.70;state.cameraPitch=0.15;state.cameraDistance=width*2.8 }
                        if angle.hasPrefix("forward") { target.z=Float(-length*0.25) }
                        if angle.hasPrefix("aft") { target.z=Float(length*0.27) }
                        if angle.hasPrefix("wing") { target=SIMD3(Float(side*aircraft.span*0.22),0,Float(length*0.03));state.cameraYaw=side*0.9;state.cameraPitch=0.8;state.cameraDistance=aircraft.span*0.38 }
                        if angle=="belly" { state.cameraYaw=0.6;state.cameraPitch = -0.8;state.cameraDistance=length*0.5 }
                        state.auditCameraTarget=target
                    }
                    else if angle=="left" || angle=="right" { state.setView(angle=="left" ? .left : .right);state.cameraDistance=48 }
                    else { state.setView(.orbit);state.cameraYaw=angle=="nose" ? -0.55 : 2.60;state.cameraPitch=0.20;state.cameraDistance=state.orbitDistance*0.68 }
                    state.qaTime=Double(argument("--qa-time") ?? "0.22") ?? 0.22
                    let file=livery.id+"-"+angle+".png"
                    do {
                        try autoreleasepool {
                            guard let command=renderer.draw(in:view,destination:target) else { throw NSError(domain:"WinglightAudit",code:1) }
                            command.waitUntilCompleted()
                            if let error=command.error { throw error }
                            let space=CGColorSpace(name:CGColorSpace.extendedLinearSRGB)!
                            guard let ci=CIImage(mtlTexture:target,options:[.colorSpace:space]),let cg=context.createCGImage(ci.oriented(.downMirrored),from:CGRect(x:0,y:0,width:1600,height:1000),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!),let destination=CGImageDestinationCreateWithURL(out.appendingPathComponent(file) as CFURL,UTType.png.identifier as CFString,1,nil) else { throw NSError(domain:"WinglightAudit",code:2) }
                            CGImageDestinationAddImage(destination,cg,nil)
                            guard CGImageDestinationFinalize(destination) else { throw NSError(domain:"WinglightAudit",code:3) }
                        }
                        images.append(file)
                    } catch { row["error"]=error.localizedDescription }
                }
                row["images"]=images;row["renderedViews"]=images.count
            }
            records.append(row)
            if let data=try? JSONSerialization.data(withJSONObject:records,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:out.appendingPathComponent("audit.json")) }
            print("AUDIT",livery.id,row["error"] ?? "OK");fflush(stdout)
        }
    }
}

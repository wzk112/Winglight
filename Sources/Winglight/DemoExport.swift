import AppKit
import AVFoundation
import CoreImage
import CoreLocation
import MetalKit
import VideoToolbox
import WinglightCore

/// Offline camera paths through the production renderer. No simulated UI or
/// replacement aircraft artwork: every frame uses the bundled geometry/shaders.
@MainActor enum DemoExport {
    struct Plan: Decodable { let output: String; let width: Int;let height: Int;let fps: Int;let shots:[Shot] }
    struct Shot: Decodable {
        let id:String;let aircraft:String;let livery:String;let duration:Double
        let background:String;let environment:String;let weather:String
        let yaw:[Double];let pitch:[Double];let distance:[Double]
        var target:[Double]?;var detail:String?;var clock:[Double]?;var wireframe:Bool?;var startTime:Double?
    }
    static func fail(_ text:String)->NSError { NSError(domain:"DemoExport",code:1,userInfo:[NSLocalizedDescriptionKey:text]) }
    static func run(plan path:String) async throws {
        let plan=try JSONDecoder().decode(Plan.self,from:Data(contentsOf:URL(fileURLWithPath:path)))
        let out=URL(fileURLWithPath:plan.output,isDirectory:true)
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        guard let device=MTLCreateSystemDefaultDevice() else { throw fail("Metal unavailable") }
        let solar=SolarController(manager:CLLocationManager(),preferences:UserDefaults(suiteName:"Winglight.DemoExport")!,automatic:false)
        let state=AppState(solar:solar);solar.followsClock=false
        state.focus=true;state.labels=false;state.flightMotion=true;state.motionIntensity=0.55;state.quality = .ultra
        let view=OrbitView(frame:NSRect(x:0,y:0,width:plan.width,height:plan.height),device:device)
        view.appState=state;view.autoResizeDrawable=false;view.drawableSize=CGSize(width:plan.width*2,height:plan.height*2)
        view.colorPixelFormat = .rgba16Float
        let renderer=Renderer(state:state);renderer.auditHeadroom=1;renderer.configure(view)
        let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:plan.width*2,height:plan.height*2,mipmapped:false)
        descriptor.usage=[.renderTarget,.shaderRead];descriptor.storageMode = .private
        guard let target=device.makeTexture(descriptor:descriptor) else { throw fail("Target allocation") }
        let context=CIContext(mtlDevice:device,options:[.cacheIntermediates:false])
        let linear=CGColorSpace(name:CGColorSpace.extendedLinearSRGB)!,srgb=CGColorSpace(name:CGColorSpace.itur_709)!
        for shot in plan.shots {
            let url=out.appendingPathComponent(shot.id+".mov")
            guard !FileManager.default.fileExists(atPath:url.path) else { print("SKIP",shot.id);continue }
            guard let aircraft=Aircraft(rawValue:shot.aircraft),let paint=Livery.matching(shot.livery,aircraft:aircraft) else { throw fail("Unknown aircraft/paint: \(shot.id)") }
            state.select(aircraft);state.livery=paint;state.qaTime=0
            state.environment=SkyEnvironment(rawValue:shot.environment)!;state.backdrop=Backdrop(rawValue:shot.background)!
            state.weather=SceneWeather(rawValue:shot.weather)!;state.wireframe=shot.wireframe ?? false
            state.auditCameraTarget=shot.target.map { SIMD3(Float($0[0]),Float($0[1]),Float($0[2])) }
            state.flightMotion=shot.detail == nil;solar.followsClock=shot.clock != nil
            if shot.clock != nil { solar.setLocation(latitude:-37.8136,longitude:144.9631,name:"墨尔本",timeZoneID:"Australia/Melbourne",persist:false) }
            renderer.updateLivery(view)
            // updateLivery publishes its loading state on the main queue.
            try await Task.sleep(nanoseconds:50_000_000)
            var attempts=0
            while state.liveryLoading && attempts<1200 { try await Task.sleep(nanoseconds:50_000_000);attempts+=1 }
            if let error=state.liveryError ?? state.rendererError { throw fail(error) }
            guard !state.liveryLoading else { throw fail("Load timeout") }
            var distanceScale=1.0
            if shot.detail == "engine",let (buffer,count)=renderer.models[state.assetID] {
                let data=buffer.contents().bindMemory(to:Float.self,capacity:count*16)
                var low=SIMD3<Float>(repeating:.greatestFiniteMagnitude),high = -low
                for i in 0..<count where data[i*16+15]==6 && data[i*16]>0 {
                    let v=SIMD3(data[i*16],data[i*16+1],data[i*16+2]);low=simd_min(low,v);high=simd_max(high,v)
                }
                let radius=max(high.x-low.x,high.y-low.y)*0.5
                var center=(low+high)*0.5;center.z+=radius*0.35
                state.auditCameraTarget=center;distanceScale=Double(radius)
            }
            let temporary=url.deletingPathExtension().appendingPathExtension("partial.mov")
            if FileManager.default.fileExists(atPath:temporary.path) { try FileManager.default.removeItem(at:temporary) }
            let writer=try AVAssetWriter(outputURL:temporary,fileType:.mov)
            let settings:[String:Any]=[AVVideoCodecKey:AVVideoCodecType.hevc,AVVideoWidthKey:plan.width,AVVideoHeightKey:plan.height,
                AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:140_000_000,AVVideoExpectedSourceFrameRateKey:plan.fps,AVVideoMaxKeyFrameIntervalKey:plan.fps*2,AVVideoProfileLevelKey:kVTProfileLevel_HEVC_Main10_AutoLevel],
                AVVideoColorPropertiesKey:[AVVideoColorPrimariesKey:AVVideoColorPrimaries_ITU_R_709_2,AVVideoTransferFunctionKey:AVVideoTransferFunction_ITU_R_709_2,AVVideoYCbCrMatrixKey:AVVideoYCbCrMatrix_ITU_R_709_2]]
            let input=AVAssetWriterInput(mediaType:.video,outputSettings:settings);input.expectsMediaDataInRealTime=false
            let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,kCVPixelBufferWidthKey as String:plan.width,kCVPixelBufferHeightKey as String:plan.height,kCVPixelBufferIOSurfacePropertiesKey as String:[:]])
            writer.add(input);guard writer.startWriting() else { throw writer.error ?? fail("Start writer") };writer.startSession(atSourceTime:.zero)
            let frames=Int((shot.duration*Double(plan.fps)).rounded())
            for frame in 0..<frames {
                while !input.isReadyForMoreMediaData { if writer.status == .failed { throw writer.error! };try await Task.sleep(nanoseconds:2_000_000) }
                try autoreleasepool {
                    let t=Double(frame)/Double(max(1,frames-1)),smooth=t*t*(3-2*t)
                    func lerp(_ a:[Double])->Double { a[0]+(a[1]-a[0])*smooth }
                    state.cameraYaw=lerp(shot.yaw);state.cameraPitch=lerp(shot.pitch);state.cameraDistance=lerp(shot.distance)*distanceScale
                    state.qaTime=(shot.startTime ?? 2)+Double(frame)/Double(plan.fps)
                    if let clock=shot.clock {
                        var cal=Calendar(identifier:.gregorian);cal.timeZone=TimeZone(identifier:"Australia/Melbourne")!
                        let midnight=cal.date(from:DateComponents(year:2026,month:10,day:25))!
                        solar.refresh(at:midnight.addingTimeInterval(lerp(clock)*3600))
                    }
                    guard let command=renderer.draw(in:view,destination:target) else { throw fail("Render frame \(frame)") }
                    command.waitUntilCompleted();if let error=command.error { throw error }
                    guard let source=CIImage(mtlTexture:target,options:[.colorSpace:linear]) else { throw fail("CI texture") }
                    let image=source.oriented(.downMirrored).applyingFilter("CILanczosScaleTransform",parameters:[kCIInputScaleKey:0.5,kCIInputAspectRatioKey:1])
                    var pixel:CVPixelBuffer?
                    guard let pool=adaptor.pixelBufferPool,CVPixelBufferPoolCreatePixelBuffer(nil,pool,&pixel)==kCVReturnSuccess,let pixel else { throw fail("Pixel buffer") }
                    context.render(image,to:pixel,bounds:CGRect(x:0,y:0,width:plan.width,height:plan.height),colorSpace:srgb)
                    guard adaptor.append(pixel,withPresentationTime:CMTime(value:Int64(frame),timescale:Int32(plan.fps))) else { throw writer.error ?? fail("Append") }
                    if frame==frames/2,let cg=context.createCGImage(image,from:image.extent,format:.RGBA8,colorSpace:srgb) {
                        let rep=NSBitmapImageRep(cgImage:cg);try rep.representation(using:.png,properties:[:])?.write(to:out.appendingPathComponent(shot.id+".png"))
                    }
                }
                if frame % (plan.fps*2)==0 { print("FRAME",shot.id,frame,"/",frames);fflush(stdout) }
            }
            input.markAsFinished();await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? fail("Finish") }
            try FileManager.default.moveItem(at:temporary,to:url)
            print("DONE",shot.id,paint.title);fflush(stdout)
        }
    }
}

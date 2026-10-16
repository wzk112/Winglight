import AppKit
import SwiftUI
import Combine
@preconcurrency import Metal
import MetalKit
import simd
import WinglightCore

private final class LiveryRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    var cancelled: Bool { lock.lock();defer { lock.unlock() };return stopped }
    func cancel() { lock.lock();stopped=true;lock.unlock() }
}

struct GPUUniforms {
    var size: SIMD2<Float>; var time: Float; var environment: Float
    var options: SIMD4<Float> // background, grid, peak, glow
    var motion: SIMD4<Float>
    var backgrounds: SIMD4<Float>
    var weather: SIMD4<Float>
    var lightning: SIMD4<Float>
}
struct GPULamp { var geometry: SIMD4<Float>; var color: SIMD4<Float>; var info: SIMD4<Float> }
struct FlowUniforms { var mvp: simd_float4x4;var viewport: SIMD4<Float>;var options: SIMD4<Float>;var field: SIMD4<Float>;var silhouette: SIMD4<Float> = .zero;var silhouetteRadius: SIMD4<Float> = .zero;var aircraftTransform: simd_float4x4 = matrix_identity_float4x4;var flowBounds: SIMD4<Float> = .zero }
struct MeshUniforms {
    var mvp: simd_float4x4; var eye: SIMD4<Float>; var options: SIMD4<Float>
    var conditions: SIMD4<Float>
    var sunlight: SIMD4<Float>
    var engineGeometry: SIMD4<Float>; var logoSource: SIMD4<Float>; var logoTarget: SIMD4<Float>
    var shadow0: simd_float4x4; var shadow1: simd_float4x4; var sun: simd_float4x4
    var weather: SIMD4<Float>; var surface: SIMD4<Float>; var lightning: SIMD4<Float>
}
@MainActor final class OrbitView: MTKView {
    weak var appState: AppState?
    private var dragLocation: NSPoint?
    var renderSubscription: AnyCancellable?
    private var windowObservers = [NSObjectProtocol]()
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowObservers.removeAll()
        for name in [NSWindow.didChangeOcclusionStateNotification, NSApplication.didHideNotification, NSApplication.didUnhideNotification, NSWindow.didChangeScreenNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRendering(); self?.resizeDrawable() }
            })
        }
        resizeDrawable(); scheduleRendering()
    }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize);resizeDrawable() }
    func resizeDrawable() {
        var scale = (window?.backingScaleFactor ?? 2)*(appState?.quality.renderScale ?? 1)
        let pixels=max(1,bounds.width*bounds.height*scale*scale)
        scale *= min(1,sqrt(33_554_432/pixels),8192/max(1,max(bounds.width,bounds.height)*scale))
        let size = CGSize(width:max(1,bounds.width*scale),height:max(1,bounds.height*scale))
        if drawableSize != size { drawableSize = size }
    }
    func scheduleRendering() {
        guard let s = appState else { return }
        let visible = window?.occlusionState.contains(.visible) ?? false
        preferredFramesPerSecond = min(s.quality.fps,window?.screen?.maximumFramesPerSecond ?? 60)
        let continuous=s.active && visible && !NSApp.isHidden
        if isPaused == continuous { (delegate as? Renderer)?.lastFrame=0 }
        // Use either display-link drawing or demand drawing, never both.
        enableSetNeedsDisplay = !continuous
        isPaused = !continuous
        if visible && !continuous { needsDisplay = true }
    }
    deinit { windowObservers.forEach { NotificationCenter.default.removeObserver($0) } }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragLocation = convert(event.locationInWindow,from:nil)
        if event.clickCount == 2 { appState?.setView(.orbit) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let s = appState else { return }
        let location = convert(event.locationInWindow,from:nil)
        defer { dragLocation = location }
        guard let previous = dragLocation else { return }
        s.viewPreset = .orbit
        s.cameraYaw -= (location.x-previous.x)*0.007
        s.cameraPitch = min(1.565,max(-1.565,s.cameraPitch-(location.y-previous.y)*0.007))
    }
    override func mouseUp(with event: NSEvent) { dragLocation = nil }
    override func scrollWheel(with event: NSEvent) {
        guard let s = appState else { return }
        let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.003 : 0.04)
        s.cameraDistance = min(220,max(32,s.cameraDistance*exp(delta)))
    }
    override func magnify(with event: NSEvent) {
        guard let s = appState else { return }
        s.cameraDistance = min(220,max(32,s.cameraDistance*exp(-event.magnification)))
    }
}
struct AircraftStage: NSViewRepresentable {
    @ObservedObject var state: AppState
    func makeCoordinator() -> Renderer { Renderer(state:state) }
    func makeNSView(context: Context) -> OrbitView {
        let view = OrbitView(frame:.zero,device:MTLCreateSystemDefaultDevice())
        view.appState = state
        view.renderSubscription=state.renderRequests.sink { [weak view] _ in view?.scheduleRendering() }
        view.colorPixelFormat = .rgba16Float
        view.colorspace = CGColorSpace(name:CGColorSpace.extendedLinearSRGB)
        // Only the explicit QA readback copies pixels out of the drawable.
        view.framebufferOnly = state.qaOutput == nil;view.autoResizeDrawable = false
        view.enableSetNeedsDisplay = true;view.isPaused = true
        view.setAccessibilityLabel("三维飞机：拖动旋转，滚动缩放，双击复位")
        context.coordinator.configure(view);view.delegate = context.coordinator
        return view
    }
    func updateNSView(_ view: OrbitView,context: Context) {
        (view.layer as? CAMetalLayer)?.wantsExtendedDynamicRangeContent = state.hdr
        view.resizeDrawable();view.scheduleRendering()
        context.coordinator.updateLivery(view)
    }
    static func dismantleNSView(_ view: OrbitView,coordinator: Renderer) { view.isPaused = true;view.delegate = nil }
}

@MainActor final class Renderer: NSObject, MTKViewDelegate {
    let state: AppState
    var queue: MTLCommandQueue?
    var composite: MTLRenderPipelineState?
    var flarePipeline: MTLRenderPipelineState?
    var shadowPipeline: MTLRenderPipelineState?
    var meshPipelines = [Int:MTLRenderPipelineState]()
    var backgroundPipelines = [Int:MTLRenderPipelineState]()
    var rainPipelines = [Int:MTLRenderPipelineState]()
    var windowMask: MTLTexture?
    var flowPipelines = [Int:MTLRenderPipelineState]()
    var flows = [String:(MTLBuffer,Int)]()
    var flowDepth: MTLDepthStencilState?
    var depthState: MTLDepthStencilState?, backgroundDepth: MTLDepthStencilState?
    var sceneTexture: MTLTexture?, depthTexture: MTLTexture?
    private var previousScene: MTLTexture?
    private var sceneTransitionStart=0.0
    private let sceneTransitionDuration=0.42
    private var renderedPreset: ViewPreset?
    var msaaColor: MTLTexture?, msaaDepth: MTLTexture?
    var shadows = [MTLTexture]()
    var shadowAircraft: String?
    var shadowSun = SIMD3<Float>(repeating:0)
    var textures = [MTLTexture]()
    var normalTextures = [MTLTexture]()
    var atlasTextures = [MTLTexture]()
    var fallbackTexture: MTLTexture?
    private var loadedLivery = Livery.neutral
    private var requestedLiveryID = ""
    private var liveryRequest: LiveryRequest?
    private let liveryQueue = DispatchQueue(label:"local.winglight.liveries",qos:.userInitiated,autoreleaseFrequency:.workItem)
    private var liveryCache = [String:[MTLTexture]]()
    private var liveryOrder = [String]()
    var textureSampler: MTLSamplerState?
    var occluders = [String:AirframeOcclusion]()
    var visibilityCache = [String:Float]()
    var visibilityEye = SIMD3<Float>(repeating:0),visibilityDirection = SIMD3<Float>(repeating:0)
    var visibilityAircraft: String?,visibilityOrthographic = false
    var models = [String:(MTLBuffer,Int)]()
    var allocatedSamples = 0, frames = 0
    var lastDisplayUpdate = 0.0
    var gpuTimings = [Double](), frameTimes = [Double](),cpuTimings = [Double]()
    var lastFrame = 0.0, perfSaved = false
    var auditHeadroom: Double?
    init(state: AppState) { self.state = state }
    func configure(_ view: MTKView) {
        guard let device = view.device else { state.rendererError = "此设备没有可用的 Metal 渲染器。";return }
        do {
            guard let url = Bundle.module.url(forResource:"Lights",withExtension:"metallib") else { throw failure("找不到预编译着色器") }
            let lib = try device.makeLibrary(URL:url)
            func make(_ vertex: String,_ fragment: String?,_ samples: Int = 1,_ depth: Bool = false,_ color: Bool = true) throws -> MTLRenderPipelineState {
                let p = MTLRenderPipelineDescriptor()
                p.vertexFunction = lib.makeFunction(name:vertex)
                if let fragment { p.fragmentFunction = lib.makeFunction(name:fragment) }
                if color { p.colorAttachments[0].pixelFormat = .rgba16Float }
                if vertex == "flowVertex" || vertex == "rainVertex" {
                    let c = p.colorAttachments[0]!
                    c.isBlendingEnabled = true;c.sourceRGBBlendFactor = .sourceAlpha;c.destinationRGBBlendFactor = .oneMinusSourceAlpha
                    c.sourceAlphaBlendFactor = .one;c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                }
                if depth { p.depthAttachmentPixelFormat = .depth32Float }
                p.rasterSampleCount = samples
                return try device.makeRenderPipelineState(descriptor:p)
            }
            composite = try make("sceneVertex","copyFragment")
            flarePipeline = try make("flareVertex","flareFragment")
            shadowPipeline = try make("shadowVertex",nil,1,true,false)
            for samples in [1,2,4] where device.supportsTextureSampleCount(samples) {
                meshPipelines[samples] = try make("meshVertex","meshFragment",samples,true)
                backgroundPipelines[samples] = try make("backgroundVertex","backgroundFragment",samples,true)
                flowPipelines[samples] = try make("flowVertex","flowFragment",samples,true)
                rainPipelines[samples] = try make("rainVertex","rainFragment",samples,true)
            }
            let dd = MTLDepthStencilDescriptor();dd.depthCompareFunction = .lessEqual;dd.isDepthWriteEnabled = true
            depthState = device.makeDepthStencilState(descriptor:dd)
            dd.isDepthWriteEnabled = false;flowDepth = device.makeDepthStencilState(descriptor:dd)
            dd.depthCompareFunction = .lessEqual;dd.isDepthWriteEnabled = false
            backgroundDepth = device.makeDepthStencilState(descriptor:dd)
            let loader = MTKTextureLoader(device:device)
            for name in ["Fuse-Main-Normal","Engine-CFM56-Normal"] {
                guard let url=Bundle.module.url(forResource:name,withExtension:"png",subdirectory:"Textures") else { throw failure("找不到表面细节纹理") }
                normalTextures.append(try loader.newTexture(URL:url,options:[.SRGB:false,.generateMipmaps:true,.textureStorageMode:MTLStorageMode.private.rawValue]))
            }
            let white=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm_srgb,width:1,height:1,mipmapped:false)
            white.storageMode = .shared
            guard let fallback=device.makeTexture(descriptor:white) else { throw failure("材质分配失败") }
            var pixel: UInt32=0xffffffff;fallback.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,withBytes:&pixel,bytesPerRow:4)
            fallbackTexture=fallback;textures=Array(repeating:fallback,count:3);atlasTextures=Array(repeating:fallback,count:16)
            let sd = MTLSamplerDescriptor();sd.minFilter = .linear;sd.magFilter = .linear;sd.mipFilter = .linear;sd.maxAnisotropy = 8
            sd.sAddressMode = .clampToEdge;sd.tAddressMode = .clampToEdge
            textureSampler = device.makeSamplerState(descriptor:sd)
            for size in [1024,1024,2048] {
                let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:size,height:size,mipmapped:false)
                d.storageMode = .private;d.usage = [.shaderRead,.renderTarget]
                guard let texture = device.makeTexture(descriptor:d) else { throw failure("阴影纹理分配失败") }
                shadows.append(texture)
            }
            queue = device.makeCommandQueue()
            if let output = state.idleOutput {
                DispatchQueue.main.asyncAfter(deadline:.now()+5) { [weak self] in
                    guard let self else { return };let start = self.frames
                    DispatchQueue.main.asyncAfter(deadline:.now()+5) { [weak self] in
                        guard let self else { return }
                        let report: [String:Any] = ["seconds":5,"startFrames":start,"endFrames":self.frames,"newFrames":self.frames-start,"active":self.state.active]
                        if let data = try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:URL(fileURLWithPath:output)) }
                    }
                }
            }
            (view.layer as? CAMetalLayer)?.wantsExtendedDynamicRangeContent = state.hdr
            if let orbit=view as? OrbitView { updateLivery(orbit) }
        } catch { state.rendererError = error.localizedDescription }
    }
    private func cacheLivery(_ key: String,_ atlases: [MTLTexture]) {
        liveryCache[key]=atlases;liveryOrder.removeAll { $0==key };liveryOrder.append(key)
        func bytes(_ entry: [MTLTexture]) -> Int { entry.reduce(0) { $0+$1.width*$1.height*4*4/3 } }
        while liveryOrder.count>1 && (liveryOrder.count>3 || liveryCache.values.reduce(0,{ $0+bytes($1) })>384*1024*1024) {
            liveryCache.removeValue(forKey:liveryOrder.removeFirst())
        }
    }
    func updateLivery(_ view: OrbitView) {
        let requested=state.livery,aircraft=state.settings.aircraft,asset=state.assetID,geometry=state.sceneGeometry
        let desired=requested.isNeutral ? Livery.defaultLivery(for:aircraft) : requested
        let key=aircraft.rawValue+"/"+requested.id
        guard requestedLiveryID != key,let device=view.device,let fallback=fallbackTexture else { return }
        requestedLiveryID=key;liveryRequest?.cancel()
        let request=LiveryRequest();liveryRequest=request
        DispatchQueue.main.async { [weak self] in
            guard let self,self.requestedLiveryID==key else { return }
            self.state.liveryLoading=true;self.state.liveryError=nil
        }
        let cachedModel=models[asset],cachedBVH=occluders[asset],cachedFlow=flows[asset],cachedTextures=liveryCache[desired.id]
        liveryQueue.async { [weak self,weak view] in
            guard !request.cancelled else { return }
            do {
                let vertexData: (MTLBuffer,Int),bvh: AirframeOcclusion,flowData: (MTLBuffer,Int)
                if let cachedModel,let cachedBVH,let cachedFlow { vertexData=cachedModel;bvh=cachedBVH;flowData=cachedFlow }
                else {
                    guard let url=Bundle.module.url(forResource:asset,withExtension:"mesh",subdirectory:"Models"),let bvhURL=Bundle.module.url(forResource:asset,withExtension:"bvh",subdirectory:"Models") else { throw NSError(domain:"Winglight",code:1,userInfo:[NSLocalizedDescriptionKey:"模型文件缺失："+asset]) }
                    let data=try Data(contentsOf:url,options:.mappedIfSafe)
                    guard data.count>0,data.count%64==0,let vertices=data.withUnsafeBytes({device.makeBuffer(bytes:$0.baseAddress!,length:data.count,options:.storageModeShared)}) else { throw NSError(domain:"Winglight",code:2) }
                    vertexData=(vertices,data.count/64)
                    guard !request.cancelled else { return }
                    bvh=try AirframeOcclusion(data:Data(contentsOf:bvhURL))
                    let lines=Airflow.avoidingAirframe(Airflow.segments(for:aircraft,geometry:geometry),mesh:bvh)
                    guard let flow=device.makeBuffer(bytes:lines,length:lines.count*MemoryLayout<Airflow.Segment>.stride,options:.storageModeShared) else { throw NSError(domain:"Winglight",code:3) }
                    flowData=(flow,lines.count)
                }
                guard !request.cancelled else { return }
                let atlases: [MTLTexture]
                if let cachedTextures { atlases=cachedTextures }
                else {
                    let urls: [URL]
                    if aircraft.isWidebody { guard let u=desired.atlasURLs,!u.isEmpty,u.count<=16 else { throw NSError(domain:"Winglight",code:4,userInfo:[NSLocalizedDescriptionKey:"涂装图集缺失"]) };urls=u }
                    else { guard let paint=desired.textureURL,let engine=desired.engineURL else { throw NSError(domain:"Winglight",code:4) };urls=[paint,engine] }
                    let loader=MTKTextureLoader(device:device)
                    var result=[MTLTexture]()
                    for url in urls {
                        guard !request.cancelled else { return }
                        result.append(try loader.newTexture(URL:url,options:[.SRGB:true,.generateMipmaps:true,.textureStorageMode:MTLStorageMode.private.rawValue]))
                    }
                    atlases=result
                }
                let maskURL=Bundle.module.url(forResource:asset+"-windows",withExtension:"png",subdirectory:"Models") ?? Bundle.module.url(forResource:aircraft.rawValue+"-windows",withExtension:"png",subdirectory:"Models")
                let mask=try maskURL.map { try MTKTextureLoader(device:device).newTexture(URL:$0,options:[.SRGB:false,.generateMipmaps:true,.textureStorageMode:MTLStorageMode.private.rawValue]) }
                guard !request.cancelled else { return }
                DispatchQueue.main.async {
                    guard let self,!request.cancelled,self.requestedLiveryID==key else { return }
                    self.windowMask=mask
                    self.models=[asset:vertexData];self.occluders=[asset:bvh];self.flows=[asset:flowData]
                    if self.state.qaTime == nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                        self.previousScene=self.sceneTexture;self.sceneTexture=nil
                        self.sceneTransitionStart=CACurrentMediaTime();self.state.beginSceneTransition(self.sceneTransitionDuration)
                    }
                    self.loadedLivery=desired;self.cacheLivery(desired.id,atlases)
                    if aircraft.isWidebody { self.atlasTextures=atlases+Array(repeating:fallback,count:16-atlases.count) }
                    else { self.textures=[atlases[0],atlases[0],atlases[1]] }
                    self.state.liveryLoading=false;self.state.liveryError=nil
                    self.shadowAircraft=nil;self.visibilityAircraft=nil
                    view?.needsDisplay=true;view?.scheduleRendering()
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self,!request.cancelled else { return }
                    self.state.liveryLoading=false;self.state.liveryError="载入失败："+error.localizedDescription
                }
            }
        }
    }
    func failure(_ text: String) -> NSError { NSError(domain:"Winglight",code:1,userInfo:[NSLocalizedDescriptionKey:text]) }
    func mtkView(_ view: MTKView,drawableSizeWillChange size: CGSize) { sceneTexture = nil;depthTexture = nil }
    func lookAt(_ eye: SIMD3<Float>,_ target: SIMD3<Float>) -> simd_float4x4 {
        let z = simd_normalize(eye-target),up = abs(z.y)>0.999 ? SIMD3<Float>(0,0,1) : SIMD3<Float>(0,1,0)
        let x = simd_normalize(simd_cross(up,z)),y = simd_cross(z,x)
        return simd_float4x4(columns:(SIMD4(x.x,y.x,z.x,0),SIMD4(x.y,y.y,z.y,0),SIMD4(x.z,y.z,z.z,0),SIMD4(-simd_dot(x,eye),-simd_dot(y,eye),-simd_dot(z,eye),1)))
    }
    func lightMatrices(sunDirection: SIMD3<Float>) -> [simd_float4x4] {
        let geometry=state.sceneGeometry
        let near: Float = 0.15,far: Float = 35,f: Float = 1/tan(.pi*0.28)
        let p = simd_float4x4(columns:(SIMD4(f,0,0,0),SIMD4(0,f,0,0),SIMD4(0,0,far/(near-far),-1),SIMD4(0,0,far*near/(near-far),0)))
        let target = SIMD3<Float>(geometry.point("logoTarget")),source=SIMD3<Float>(geometry.point("logo"))
        let left = p*lookAt(SIMD3(-abs(source.x),source.y,source.z),target)
        let right = p*lookAt(SIMD3(abs(source.x),source.y,source.z),target)
        let scale=Float(max(30,geometry.length*0.65,geometry.span*0.65))
        let ortho = simd_float4x4(columns:(SIMD4(1/scale,0,0,0),SIMD4(0,1/scale,0,0),SIMD4(0,0,-1/(scale*5),0),SIMD4(0,0,0,1)))
        return [left,right,ortho*lookAt(sunDirection*scale*3,SIMD3(0,0,0))]
    }
    func modelTransform() -> simd_float4x4 {
        guard state.flightAmount > 0 && state.viewPreset == .orbit else { return matrix_identity_float4x4 }
        let t = Float(state.flightTime),amount = Float(state.motionIntensity*state.flightAmount)
        let bank = (sin(t*0.42)*0.060+sin(t*0.17)*0.018)*amount
        let pitch = (sin(t*0.34)*0.024+sin(t*0.71)*0.005)*amount
        let roll = simd_float4x4(simd_quatf(angle:bank,axis:SIMD3(0,0,1)))
        var transform = roll*simd_float4x4(simd_quatf(angle:pitch,axis:SIMD3(1,0,0)))
        transform.columns.3.y = (sin(t*0.56)*0.42+sin(t*0.23)*0.12)*amount
        transform.columns.3.x = sin(t*0.29)*0.16*amount
        return transform
    }
    func camera(aspect: Float) -> (simd_float4x4,SIMD3<Float>,SIMD3<Float>) {
        let yaw = Float(state.cameraYaw), pitch = Float(state.cameraPitch), distance = Float(state.cameraDistance)
        let target = state.auditCameraTarget ?? SIMD3<Float>(0,1.0,0)
        let direction = SIMD3<Float>(sin(yaw)*cos(pitch),sin(pitch),-cos(yaw)*cos(pitch))
        let eye = target+direction*distance
        let z = direction, x = simd_normalize(simd_cross(SIMD3<Float>(0,1,0),z)), y = simd_cross(z,x)
        let view = simd_float4x4(columns:(SIMD4(x.x,y.x,z.x,0),SIMD4(x.y,y.y,z.y,0),SIMD4(x.z,y.z,z.z,0),SIMD4(-simd_dot(x,eye),-simd_dot(y,eye),-simd_dot(z,eye),1)))
        let near: Float = 0.5, far: Float = 400
        var projection: simd_float4x4
        if state.viewPreset == .orbit {
            let f = 1/tan(Float.pi/9)
            projection = simd_float4x4(columns:(SIMD4(f/aspect,0,0,0),SIMD4(0,f,0,0),SIMD4(0,0,far/(near-far),-1),SIMD4(0,0,far*near/(near-far),0)))
        } else {
            let halfHeight = Float(state.settings.aircraft.length)*0.60*distance/76
            projection = simd_float4x4(columns:(SIMD4(1/(halfHeight*aspect),0,0,0),SIMD4(0,1/halfHeight,0,0),SIMD4(0,0,1/(near-far),0),SIMD4(0,0,near/(near-far),1)))
        }
        return (projection*view,eye,direction)
    }
    func draw(in view: MTKView) { draw(in:view,destination:nil) }
    @discardableResult func draw(in view: MTKView,destination: MTLTexture?) -> MTLCommandBuffer? {
        let cpuStart=CACurrentMediaTime()
        state.updateMotion()
        let requestedSamples = state.quality.samples
        let samples = meshPipelines[requestedSamples] != nil ? requestedSamples : 1
        guard let device = view.device, let composite, let flarePipeline, let shadowPipeline, let meshPipeline = meshPipelines[samples], let backgroundPipeline = backgroundPipelines[samples], let queue,
              let (vertices,vertexCount) = models[state.assetID], view.bounds.width > 20, view.bounds.height > 20 else { return nil }
        let now = CACurrentMediaTime(), screen = view.window?.screen ?? NSScreen.main
        let current = auditHeadroom ?? Double(screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1)
        let lightning=StormLighting.sample(time:state.backgroundTime,strength:state.weatherValue.w,headroom:current,hdr:state.hdr,reduceMotion:NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        if now-lastDisplayUpdate > 1 {
            lastDisplayUpdate = now
            DispatchQueue.main.async { [weak self] in self?.state.updateDisplay(screen) }
        }
        let w = Int(view.drawableSize.width),h = Int(view.drawableSize.height),backing = view.drawableSize.width/view.bounds.width
        if sceneTexture == nil || sceneTexture?.width != w || sceneTexture?.height != h || allocatedSamples != samples {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:w,height:h,mipmapped:false)
            d.usage = [.renderTarget,.shaderRead];d.storageMode = .private
            sceneTexture = device.makeTexture(descriptor:d)
            d.pixelFormat = .depth32Float;depthTexture = device.makeTexture(descriptor:d)
            if samples > 1 {
                d.textureType = .type2DMultisample;d.sampleCount = samples;d.usage = .renderTarget;d.storageMode = device.hasUnifiedMemory ? .memoryless : .private
                msaaDepth = device.makeTexture(descriptor:d);d.pixelFormat = .rgba16Float;msaaColor = device.makeTexture(descriptor:d)
            }
            allocatedSamples = samples
            let label = "\(w) × \(h)"
            DispatchQueue.main.async { [weak self] in
                if self?.state.renderResolution != label { self?.state.renderResolution = label }
            }
        }
        let drawable = destination == nil ? view.currentDrawable : nil
        let pass: MTLRenderPassDescriptor
        if let destination {
            pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=destination;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
        } else { guard let descriptor=view.currentRenderPassDescriptor else { return nil };pass=descriptor }
        guard let sceneTexture,let depthTexture,let outputTexture=destination ?? drawable?.texture,let buffer = queue.makeCommandBuffer() else { return nil }
        if let previous=renderedPreset,previous != state.viewPreset,state.qaTime == nil,!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            previousScene=self.sceneTexture;self.sceneTexture=nil
            sceneTransitionStart=CACurrentMediaTime();state.beginSceneTransition(sceneTransitionDuration)
            // Allocate the new scene on the next frame; preserve this complete frame.
            renderedPreset=state.viewPreset;(view as? OrbitView)?.scheduleRendering();return nil
        }
        renderedPreset=state.viewPreset
        let (cameraMVP,worldEye,worldDirection) = camera(aspect:Float(w)/Float(h))
        let model = modelTransform(),inverse = model.inverse
        var framing = matrix_identity_float4x4
        framing.columns.3.x = state.focus ? 0 : Float(246/view.bounds.width)
        let mvp = framing*cameraMVP*model,eye = (inverse*SIMD4(worldEye,1)).xyz,direction = (inverse*SIMD4(worldDirection,0)).xyz
        let orthographic=state.viewPreset != .orbit
        if visibilityEye != eye || visibilityDirection != direction || visibilityAircraft != state.assetID || visibilityOrthographic != orthographic {
            visibilityCache.removeAll(keepingCapacity:true);visibilityEye=eye;visibilityDirection=direction;visibilityAircraft=state.assetID;visibilityOrthographic=orthographic
        }
        let sunDirection = simd_normalize((inverse*SIMD4(state.sunDirection,0)).xyz)
        let sunChanged = simd_distance(sunDirection,shadowSun)>0.002 || shadowAircraft != state.assetID
        if sunChanged { shadowSun = sunDirection }
        let matrices = lightMatrices(sunDirection:shadowSun)
        var meshUniforms = MeshUniforms(mvp:mvp,eye:SIMD4(eye,1),options:SIMD4(state.auditUnlit ? 2 : (state.wireframe ? 1 : 0),state.settings.logo ? 1 : 0,!state.livery.isNeutral && loadedLivery.aircraft == state.settings.aircraft.rawValue ? (loadedLivery.engineTexture == nil ? 1 : 2) : 0,state.settings.aircraft.isWidebody ? 2 : (state.settings.aircraft == .airbus ? 0 : 1)),conditions:SIMD4(Float(state.flightTime),state.environmentValue,state.backgroundWeights.z,state.sunDirection.y),sunlight:SIMD4(sunDirection,state.solar.followsClock && state.solar.position != nil ? 1 : 0),engineGeometry:SIMD4(Float(state.sceneGeometry.engineXY[0]),Float(state.sceneGeometry.engineXY[1]),state.backgroundWeights.w,0),logoSource:SIMD4(SIMD3<Float>(state.sceneGeometry.point("logo")),1),logoTarget:SIMD4(SIMD3<Float>(state.sceneGeometry.point("logoTarget")),1),shadow0:matrices[0],shadow1:matrices[1],sun:matrices[2],weather:state.weatherValue,surface:SIMD4(state.cabinLights ? 1 : 0,windowMask == nil ? 0 : 1,Float(state.backgroundTime),NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0),lightning:lightning)
        var u = GPUUniforms(size:SIMD2(Float(w),Float(h)),time:Float(state.backgroundTime),environment:state.environmentValue,options:SIMD4(state.backdrop.index,state.grid && !state.focus ? 1 : 0,Float(Lighting.peak(headroom:current,hdr:state.hdr,strength:state.strength)),Float(state.glow)),motion:SIMD4(Float(state.motionIntensity),0,0,NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0),backgrounds:state.backgroundWeights,weather:state.weatherValue,lightning:lightning)
        // Aircraft, lights and shadow maps share model space. Whole-airframe motion
        // never separates lights from their housings or invalidates occlusion.
        if shadowAircraft != state.assetID || sunChanged {
            for i in 0..<3 where i == 2 || shadowAircraft != state.assetID {
                let p = MTLRenderPassDescriptor();p.depthAttachment.texture = shadows[i];p.depthAttachment.loadAction = .clear;p.depthAttachment.storeAction = .store;p.depthAttachment.clearDepth = 1
                if let enc = buffer.makeRenderCommandEncoder(descriptor:p) {
                    enc.label = "Cached aircraft shadow \(i)";enc.setRenderPipelineState(shadowPipeline);enc.setDepthStencilState(depthState)
                    enc.setVertexBuffer(vertices,offset:0,index:0)
                    var matrix = matrices[i];enc.setVertexBytes(&matrix,length:64,index:1)
                    enc.setDepthBias(1.2,slopeScale:1.5,clamp:0.001)
                    enc.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:vertexCount);enc.endEncoding()
                }
            }
            shadowAircraft = state.assetID
        }
        let scenePass = MTLRenderPassDescriptor()
        scenePass.colorAttachments[0].texture = samples > 1 ? msaaColor : sceneTexture
        scenePass.colorAttachments[0].resolveTexture = samples > 1 ? sceneTexture : nil
        scenePass.colorAttachments[0].loadAction = .clear;scenePass.colorAttachments[0].storeAction = samples > 1 ? .multisampleResolve : .store
        scenePass.depthAttachment.texture = samples > 1 ? msaaDepth : depthTexture
        scenePass.depthAttachment.resolveTexture = samples > 1 && state.qaOutput != nil ? depthTexture : nil
        scenePass.depthAttachment.loadAction = .clear;scenePass.depthAttachment.storeAction = state.qaOutput != nil ? (samples > 1 ? .multisampleResolve : .store) : .dontCare
        scenePass.depthAttachment.depthResolveFilter = .min;scenePass.depthAttachment.clearDepth = 1
        if let enc = buffer.makeRenderCommandEncoder(descriptor:scenePass) {
            enc.label = "MSAA environment and aircraft"
            enc.setRenderPipelineState(meshPipeline);enc.setDepthStencilState(depthState);enc.setCullMode(.none)
            enc.setVertexBuffer(vertices,offset:0,index:0)
            enc.setVertexBytes(&meshUniforms,length:MemoryLayout<MeshUniforms>.stride,index:1)
            enc.setFragmentBytes(&meshUniforms,length:MemoryLayout<MeshUniforms>.stride,index:1)
            for i in 0..<textures.count { enc.setFragmentTexture(textures[i],index:i) }
            for i in 0..<atlasTextures.count { enc.setFragmentTexture(atlasTextures[i],index:i+8) }
            for i in 0..<shadows.count { enc.setFragmentTexture(shadows[i],index:i+3) }
            for i in 0..<normalTextures.count { enc.setFragmentTexture(normalTextures[i],index:i+6) }
            enc.setFragmentTexture(windowMask ?? fallbackTexture,index:24)
            enc.setFragmentSamplerState(textureSampler,index:0)
            enc.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:vertexCount)
            // Shade the far background only at uncovered MSAA samples. Keep it
            // before blended flow/rain so their original composition is intact.
            enc.setRenderPipelineState(backgroundPipeline);enc.setDepthStencilState(backgroundDepth)
            enc.setFragmentBytes(&u,length:MemoryLayout<GPUUniforms>.stride,index:0)
            enc.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
            if state.backgroundWeights.y > 0.001,let pipeline = flowPipelines[samples],let (lines,count) = flows[state.assetID] {
                var flow = FlowUniforms(mvp:framing*cameraMVP,viewport:SIMD4(Float(w),Float(h),Float(backing)*0.72,Float(Airflow.samples)),options:SIMD4(Float(state.backgroundTime),state.environmentValue,Float(state.motionIntensity),state.backgroundWeights.y),field:SIMD4(Float(state.settings.aircraft.length/39.47),0.26,0,0))
                func pixel(_ p: SIMD3<Float>) -> SIMD2<Float> {
                    let clip=mvp*SIMD4(p,1),ndc=SIMD2(clip.x,clip.y)/max(0.01,clip.w)
                    return SIMD2((ndc.x*0.5+0.5)*Float(w),(0.5-ndc.y*0.5)*Float(h))
                }
                let bodyY=Float(state.sceneGeometry.bodyCenterY),bodyRadius=Float(state.settings.aircraft.bodyWidth)*0.5
                let a=pixel(SIMD3(0,bodyY,-Float(state.settings.aircraft.length)*0.42)),b=pixel(SIMD3(0,bodyY,Float(state.settings.aircraft.length)*0.42))
                let center=pixel(SIMD3(0,bodyY,0))
                let radius=max(simd_distance(center,pixel(SIMD3(0,bodyY+bodyRadius,0))),simd_distance(center,pixel(SIMD3(bodyRadius,bodyY,0))))
                flow.aircraftTransform=model;flow.flowBounds=Airflow.motionBounds(for:state.sceneGeometry)
                flow.silhouette=SIMD4(a.x,a.y,b.x,b.y);flow.silhouetteRadius=SIMD4(radius,0,0,0)
                enc.setRenderPipelineState(pipeline);enc.setDepthStencilState(flowDepth)
                enc.setVertexBuffer(lines,offset:0,index:0)
                enc.setVertexBytes(&flow,length:MemoryLayout<FlowUniforms>.stride,index:1)
                enc.setFragmentBytes(&flow,length:MemoryLayout<FlowUniforms>.stride,index:1)
                enc.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:6,instanceCount:count)
            }
            if state.weatherValue.y > 0.001,let rainPipeline=rainPipelines[samples] {
                var rain=FlowUniforms(mvp:framing*cameraMVP,viewport:SIMD4(Float(w),Float(h),Float(backing),0),options:SIMD4(Float(state.backgroundTime),state.environmentValue,state.weatherValue.y,lightning.x),field:SIMD4(Float(max(60,state.settings.aircraft.length*1.2)),worldEye.x,worldEye.y,worldEye.z))
                enc.setRenderPipelineState(rainPipeline);enc.setDepthStencilState(flowDepth)
                enc.setVertexBytes(&rain,length:MemoryLayout<FlowUniforms>.stride,index:1)
                enc.setFragmentBytes(&rain,length:MemoryLayout<FlowUniforms>.stride,index:1)
                enc.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:6,instanceCount:8000)
            }
            enc.endEncoding()
        }
        let lamps = state.frameLamps()
        var diagnostics = [[String:Any]]()
        var gpu = lamps.map { lamp -> GPULamp in
            let position = SIMD3<Float>(lamp.position),clip = mvp*SIMD4(position,1)
            let ndc = SIMD3(clip.x,clip.y,clip.z)/clip.w
            let screenPoint = SIMD2((ndc.x+1)*0.5*Float(w),(1-ndc.y)*0.5*Float(h))
            let toward = state.viewPreset == .orbit ? eye-position : direction
            let angular = Lighting.angularGain(lamp.emission,toward:SIMD3<Double>(toward))
            let visible = clip.w > 0 && ndc.z > 0 && ndc.z < 1 && abs(ndc.x) < 1 && abs(ndc.y) < 1
            let distance = state.viewPreset == .orbit ? Double(simd_length(eye-position)) : state.cameraDistance
            let naturalRadius = state.coreSize*backing*lamp.radius*76/max(1,distance)
            let pixelRadius = max(0.65,naturalRadius),subpixelFlux = min(1,pow(naturalRadius/pixelRadius,2))
            let transmission=exp(-distance*Double(state.weatherValue.z)*0.009)
            let intensity = visible ? lamp.intensity*angular*subpixelFlux*transmission : 0
            let flash = lamp.kind == .strobe || lamp.kind == .beacon
            // Diagnostic depth tolerance is half a millimetre in world space.
            let nearClip = mvp*SIMD4(position+simd_normalize(toward)*0.0005,1)
            let tolerance = max(0.0000001,abs(ndc.z-nearClip.z/nearClip.w))
            let visibility: Float
            if intensity<=0 && state.qaOutput == nil { visibility=0 }
            else if let cached=visibilityCache[lamp.id] { visibility=cached }
            else {
                visibility=occluders[state.assetID]?.visibility(from:position,toward:toward,distance:Float(distance),radius:lamp.kind == .landing ? 0.06 : 0.025,orthographic:orthographic) ?? 0
                visibilityCache[lamp.id]=visibility
            }
            let occluded = visibility == 0
            if state.qaOutput != nil {
                diagnostics.append(["rayOccluded":occluded,"visibleFraction":Double(visibility),"id":lamp.id,"x":Double(screenPoint.x),"y":Double(screenPoint.y),"depth":Double(ndc.z),"depthTolerance":Double(tolerance),"angularGain":angular,"pulse":lamp.intensity,"preOcclusionIntensity":intensity])
            }
            return GPULamp(geometry:SIMD4(screenPoint.x,screenPoint.y,Float(pixelRadius),Float(intensity)*visibility),color:SIMD4(lamp.rgb,1),info:SIMD4(flash ? 1 : 0,occluded ? 1 : 0,ndc.z,tolerance))
        }
        if let enc = buffer.makeRenderCommandEncoder(descriptor:pass) {
            enc.label = "EDR composition and bounded light sprites"
            enc.setRenderPipelineState(composite);enc.setFragmentTexture(sceneTexture,index:0)
            var blend=Float(min(1,max(0,(now-sceneTransitionStart)/sceneTransitionDuration)))
            blend=blend*blend*(3-2*blend)
            if previousScene == nil || previousScene?.width != w || previousScene?.height != h { blend=1 }
            enc.setFragmentTexture(previousScene ?? sceneTexture,index:1);enc.setFragmentBytes(&blend,length:4,index:0)
            if blend>=1 { previousScene=nil }
            enc.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
            enc.setRenderPipelineState(flarePipeline)
            enc.setVertexBytes(&u,length:MemoryLayout<GPUUniforms>.stride,index:0)
            enc.setFragmentBytes(&u,length:MemoryLayout<GPUUniforms>.stride,index:0)
            enc.setVertexBytes(&gpu,length:MemoryLayout<GPULamp>.stride*gpu.count,index:1)
            enc.setFragmentBytes(&gpu,length:MemoryLayout<GPULamp>.stride*gpu.count,index:1)
            enc.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:6,instanceCount:gpu.count);enc.endEncoding()
        }
        frames += 1
        if let output = state.qaOutput, !state.qaCaptured, !state.liveryLoading, frames > 90, state.qaTime != nil || lamps.contains(where:{$0.kind == .strobe && $0.intensity > 0.99}) {
            state.qaCaptured = true
            let row = ((w*8+255)/256)*256, depthRow = ((w*4+255)/256)*256
            if let staging = device.makeBuffer(length:row*h,options:.storageModeShared),let depths = device.makeBuffer(length:depthRow*h,options:.storageModeShared),let blit = buffer.makeBlitCommandEncoder() {
                blit.copy(from:outputTexture,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:w,height:h,depth:1),to:staging,destinationOffset:0,destinationBytesPerRow:row,destinationBytesPerImage:row*h)
                blit.copy(from:depthTexture,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:w,height:h,depth:1),to:depths,destinationOffset:0,destinationBytesPerRow:depthRow,destinationBytesPerImage:depthRow*h);blit.endEncoding()
                let model = state.settings.aircraft.title,hdr = state.hdr,peak = Double(u.options.z),preset = state.viewPreset.rawValue,diag = diagnostics, cameraPose = [state.cameraYaw,state.cameraPitch,state.cameraDistance], sampleCount = samples, renderScale = state.quality.renderScale, environment = state.environment.rawValue, backdrop = state.backdrop.rawValue, livery = state.livery.rawValue
                let weatherName=state.weather.rawValue
                let solar: [String:Any] = ["enabled":state.solar.followsClock,"elevation":state.solar.position?.elevation ?? 0,"azimuth":state.solar.position?.azimuth ?? 0,"date":ISO8601DateFormatter().string(from:state.solar.date),"sunrise":state.solar.clock(state.solar.events?.sunrise),"sunset":state.solar.clock(state.solar.events?.sunset),"environmentValue":state.environmentValue]
                let backgroundTime=state.backgroundTime,backgroundMotion=state.backgroundMotion
                buffer.addCompletedHandler { _ in
                    let pixels = staging.contents().bindMemory(to:UInt16.self,capacity:row*h/2)
                    let z = depths.contents().bindMemory(to:Float.self,capacity:depthRow*h/4)
                    var maximum: Float = 0,extended = 0
                    for y in 0..<h { for x in 0..<w {
                        let i = y*(row/2)+x*4
                        let value = max(Float(Float16(bitPattern:pixels[i])),max(Float(Float16(bitPattern:pixels[i+1])),Float(Float16(bitPattern:pixels[i+2]))))
                        maximum = max(maximum,value);if value > 1.001 { extended += 1 }
                    }}
                    let tested = diag.map { entry -> [String:Any] in
                        var d = entry
                        let x = max(0,min(w-1,Int(entry["x"] as! Double))), y = max(0,min(h-1,Int(entry["y"] as! Double)))
                        let surface = Double(z[y*(depthRow/4)+x]), lamp = entry["depth"] as! Double
                        d["surfaceDepth"] = surface;d["rasterOccluded"] = lamp > surface+(entry["depthTolerance"] as! Double);d["occluded"] = entry["rayOccluded"]
                        return d
                    }
                    let report: [String:Any] = ["aircraft":model,"msaaSamples":sampleCount,"renderScale":renderScale,"environment":environment,"weather":weatherName,"lightningAmplitude":lightning.x,"solar":solar,"backgroundTime":backgroundTime,"backgroundMotion":backgroundMotion,"backdrop":backdrop,"livery":livery,"view":preset,"cameraYawPitchDistance":cameraPose,"hdrEnabled":hdr,"pixelFormat":"rgba16Float","colorSpace":"extendedLinearSRGB","screenHeadroom":current,"requestedPeak":peak,"gpuMaximumRGB":maximum,"pixelsAboveSDR":extended,"width":w,"height":h,"lamps":tested]
                    if let data = try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:URL(fileURLWithPath:output)) }
                }
            }
        }
        if state.perfOutput != nil && !perfSaved && frames > 30 {
            // A covered/hidden window deliberately pauses its display link.
            // Do not count that idle interval as a rendered frame duration.
            if lastFrame > 0 { frameTimes.append((now-lastFrame)*1000) };cpuTimings.append((CACurrentMediaTime()-cpuStart)*1000)
            buffer.addCompletedHandler { [weak self] cb in
                let gpuMS = (cb.gpuEndTime-cb.gpuStartTime)*1000
                DispatchQueue.main.async {
                    guard let self, !self.perfSaved else { return }
                    self.gpuTimings.append(gpuMS)
                    if self.gpuTimings.count >= self.state.perfFrames,let path = self.state.perfOutput {
                        self.perfSaved = true
                        let sorted = self.gpuTimings.sorted()
                        let report: [String:Any] = ["device":device.name,"frames":sorted.count,"gpuMeanMS":sorted.reduce(0,+)/Double(sorted.count),"gpuP95MS":sorted[Int(Double(sorted.count-1)*0.95)],"gpuMaxMS":sorted.last ?? 0,"frameMeanMS":self.frameTimes.reduce(0,+)/Double(max(1,self.frameTimes.count)),"frameP95MS":self.frameTimes.sorted()[max(0,Int(Double(self.frameTimes.count-1)*0.95))],"cpuMeanMS":self.cpuTimings.reduce(0,+)/Double(max(1,self.cpuTimings.count)),"cpuP95MS":self.cpuTimings.sorted()[max(0,Int(Double(self.cpuTimings.count-1)*0.95))],"width":w,"height":h,"msaaSamples":samples,"quality":self.state.quality.rawValue]
                        if let data = try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:URL(fileURLWithPath:path)) }
                    }
                }
            }
        }
        lastFrame = now
        if let drawable { buffer.present(drawable) };buffer.commit()
        if !state.active { view.isPaused=true;view.enableSetNeedsDisplay=true }
        return buffer
    }
}
private extension SIMD4 where Scalar == Float { var xyz: SIMD3<Float> { SIMD3(x,y,z) } }

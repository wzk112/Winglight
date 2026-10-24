import SwiftUI
import MetalKit
import Combine
import WinglightCore

@MainActor final class OrbitView: MTKView {
    weak var appState: AppState?
    var renderSubscription: AnyCancellable?
    private var observers = [NSObjectProtocol]()
    override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame:frame,device:device)
        let pan=UIPanGestureRecognizer(target:self,action:#selector(orbit(_:)))
        pan.maximumNumberOfTouches=1;addGestureRecognizer(pan)
        addGestureRecognizer(UIPinchGestureRecognizer(target:self,action:#selector(zoom(_:))))
        let reset=UITapGestureRecognizer(target:self,action:#selector(resetCamera))
        reset.numberOfTapsRequired=2;addGestureRecognizer(reset)
        for name in [UIScene.didActivateNotification,UIScene.willDeactivateNotification,UIApplication.didBecomeActiveNotification,UIApplication.willResignActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRendering() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName:UIApplication.didReceiveMemoryWarningNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { (self?.delegate as? Renderer)?.releaseInactiveResources() }
        })
    }
    required init(coder: NSCoder) { fatalError("Use init(frame:device:)") }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    override func didMoveToWindow() { super.didMoveToWindow();resizeDrawable();scheduleRendering() }
    override func layoutSubviews() { super.layoutSubviews();resizeDrawable();scheduleRendering() }
    func resizeDrawable() {
        var scale=(window?.windowScene?.screen.scale ?? contentScaleFactor)*(appState?.quality.renderScale ?? 1)
        let pixels=max(1,bounds.width*bounds.height*scale*scale)
        // Keep all scene data; bound render-target allocation on mobile GPUs.
        scale *= min(1,sqrt(16_777_216/pixels),8192/max(1,max(bounds.width,bounds.height)*scale))
        let size=CGSize(width:max(1,bounds.width*scale),height:max(1,bounds.height*scale))
        if drawableSize != size { drawableSize=size }
    }
    func scheduleRendering() {
        guard let s=appState else { return }
        let visible=window?.windowScene?.activationState == .foregroundActive && !isHidden
        let fps=min(s.quality.fps,window?.windowScene?.screen.maximumFramesPerSecond ?? 60)
        if preferredFramesPerSecond != fps { preferredFramesPerSecond=fps }
        let continuous=s.active && visible
        if isPaused == continuous { (delegate as? Renderer)?.lastFrame=0 }
        if enableSetNeedsDisplay == continuous { enableSetNeedsDisplay = !continuous }
        if isPaused == continuous { isPaused = !continuous }
        if visible && !continuous { setNeedsDisplay() }
    }
    @objc private func orbit(_ gesture: UIPanGestureRecognizer) {
        guard let s=appState else { return }
        let delta=gesture.translation(in:self);gesture.setTranslation(.zero,in:self)
        if s.viewPreset != .orbit { s.viewPreset = .orbit }
        s.cameraYaw -= delta.x*0.007
        s.cameraPitch=min(1.565,max(-1.565,s.cameraPitch+delta.y*0.007))
    }
    @objc private func zoom(_ gesture: UIPinchGestureRecognizer) {
        guard let s=appState else { return }
        s.cameraDistance=min(220,max(32,s.cameraDistance/gesture.scale));gesture.scale=1
    }
    @objc private func resetCamera() { appState?.setView(.orbit) }
}

struct AircraftStage: UIViewRepresentable {
    @ObservedObject var state: AppState
    func makeCoordinator() -> Renderer { Renderer(state:state) }
    func makeUIView(context: Context) -> OrbitView {
        let view=OrbitView(frame:.zero,device:MTLCreateSystemDefaultDevice())
        view.appState=state
        view.renderSubscription=state.renderRequests.sink { [weak view] _ in view?.scheduleRendering() }
        view.colorPixelFormat = .rgba16Float
        (view.layer as? CAMetalLayer)?.colorspace=CGColorSpace(name:CGColorSpace.extendedLinearSRGB)
        view.framebufferOnly=state.qaOutput == nil;view.autoResizeDrawable=false
        view.enableSetNeedsDisplay=true;view.isPaused=true
        view.accessibilityLabel="三维飞机：拖动旋转，双指捏合缩放，双击复位"
        view.accessibilityIdentifier="aircraftStage"
        view.delegate=context.coordinator
        let renderer=context.coordinator
        DispatchQueue.main.async { [weak view] in
            guard let view else { return };renderer.configure(view);view.scheduleRendering()
        }
        return view
    }
    func updateUIView(_ view: OrbitView,context: Context) {
        (view.layer as? CAMetalLayer)?.wantsExtendedDynamicRangeContent=state.hdr
        view.resizeDrawable();view.scheduleRendering()
        let renderer=context.coordinator
        DispatchQueue.main.async { [weak view] in
            guard let view,renderer.queue != nil else { return };renderer.updateLivery(view)
        }
    }
    static func dismantleUIView(_ view: OrbitView,coordinator: Renderer) { view.isPaused=true;view.delegate=nil }
}

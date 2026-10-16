import AppKit
import Combine
import CoreLocation
import WinglightCore

@MainActor protocol LocationProvider: AnyObject {
    var delegate: CLLocationManagerDelegate? { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    var desiredAccuracy: CLLocationAccuracy { get set }
    func requestWhenInUseAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
}
extension CLLocationManager: LocationProvider {}

@MainActor final class SolarController: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    enum RequestPhase { case idle, permission, acquiring }
    @Published var followsClock = true { didSet { if followsClock != oldValue { sceneChanges.send() } } }
    let sceneChanges = PassthroughSubject<Void,Never>()
    private(set) var position: Solar.Position?
    private(set) var events: Solar.Events?
    @Published private(set) var locationName = "未设置地点"
    @Published private(set) var status = "定位后可自动匹配日照，也可手动选城市。"
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var date = Date()
    private(set) var manualDate: Date?
    private(set) var returningToNow = false
    private var timeTransition: Timer?
    private var scrubTimer: Timer?
    private var pendingHour: Double?
    private(set) var isScrubbing = false
    private let clockFormatter = DateFormatter()
    private var calendar = Calendar(identifier:.gregorian)
    @Published private(set) var phaseOfRequest = RequestPhase.idle
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var locationIssue = false
    @Published private(set) var usesMacLocation = false
    @Published private(set) var lastFixDate: Date?
    private let manager: LocationProvider
    private let preferences: UserDefaults
    private let now: () -> Date
    private var timer: Timer?, deadlineTimer: Timer?
    private var deadline: Date?
    private var eventDay: Date?
    private var wantsInitialFix = false
    var timeZone = TimeZone.current { didSet { calendar.timeZone=timeZone;clockFormatter.timeZone=timeZone;eventDay=nil } }
    var requesting: Bool { phaseOfRequest != .idle }
    var requestTitle: String { phaseOfRequest == .permission ? "等待系统授权" : "正在获取位置" }
    var authorizationLabel: String {
        switch authorization {
        case .authorizedAlways: return "已允许"
        case .denied: return "未允许"
        case .restricted: return "受系统限制"
        default: return "尚未授权"
        }
    }
    override convenience init() {
        let args=CommandLine.arguments
        let diagnostic=["--qa-output","--perf-output","--idle-output","--latitude"].contains(where:args.contains)
        self.init(manager:CLLocationManager(),preferences:.standard,automatic:!diagnostic)
    }
    init(manager: LocationProvider, preferences: UserDefaults, now: @escaping () -> Date = Date.init, automatic: Bool = true) {
        self.manager=manager;self.preferences=preferences;self.now=now
        super.init()
        calendar.timeZone=timeZone;clockFormatter.dateFormat="HH:mm";clockFormatter.timeZone=timeZone
        // Acquire one available fix, then stop hardware updates.
        manager.desiredAccuracy=kCLLocationAccuracyBest
        authorization=manager.authorizationStatus;manager.delegate=self
        if let saved=preferences.dictionary(forKey:"solarManualLocation"),
           let lat=saved["latitude"] as? Double,let lon=saved["longitude"] as? Double,let name=saved["name"] as? String {
            applyLocation(latitude:lat,longitude:lon,name:name,timeZoneID:saved["timeZone"] as? String)
            status="使用手动地点"
        }
        wantsInitialFix=automatic && coordinate == nil
        if automatic {
            timer=Timer.scheduledTimer(withTimeInterval:30,repeats:true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            };timer?.tolerance=5
            if coordinate == nil && isAuthorized {
                DispatchQueue.main.async { [weak self] in
                    guard let self,self.coordinate == nil,self.wantsInitialFix else { return };self.locate()
                }
            }
        }
    }
    deinit { timer?.invalidate();deadlineTimer?.invalidate();timeTransition?.invalidate();scrubTimer?.invalidate() }
    private var isAuthorized: Bool { authorization == .authorizedAlways }
    func locate() {
        // An earlier requestLocation failure can leave Core Location's one-shot
        // request pending. Explicitly stop it before every new bounded session.
        finishRequest();wantsInitialFix=false
        authorization=manager.authorizationStatus;locationIssue=false
        switch authorization {
        case .notDetermined:
            phaseOfRequest = .permission;status="请在 macOS 提示中允许位置访问。"
            armDeadline(seconds:45);manager.requestWhenInUseAuthorization()
        case .authorizedAlways: beginUpdates()
        case .denied, .restricted: fail("定位未获允许。可打开系统定位设置，或手动选择城市。")
        @unknown default: fail("系统定位状态不可用，可重试或手动选择城市。")
        }
    }
    private func beginUpdates() {
        guard phaseOfRequest != .acquiring else { return }
        manager.stopUpdatingLocation()
        phaseOfRequest = .acquiring;locationIssue=false
        status="正在通过系统定位获取位置，最多等待 20 秒。"
        armDeadline(seconds:20)
        // Continuous updates tolerate temporary locationUnknown errors and are
        // always stopped after a valid fix, cancellation or our own deadline.
        manager.startUpdatingLocation()
    }
    private func armDeadline(seconds: TimeInterval) {
        deadlineTimer?.invalidate();deadline=now().addingTimeInterval(seconds)
        deadlineTimer=Timer.scheduledTimer(withTimeInterval:seconds,repeats:false) { [weak self] _ in
            MainActor.assumeIsolated { self?.expireLocationRequest() }
        }
    }
    func checkLocationDeadline() {
        guard requesting,let deadline,now() >= deadline else { return }
        expireLocationRequest()
    }
    private func expireLocationRequest() {
        guard requesting else { return }
        let awaitingPermission=phaseOfRequest == .permission
        fail(awaitingPermission ? "尚未收到系统授权。可重试，或打开系统定位设置。" : "系统已允许定位，但 20 秒内未返回位置。可以重试，或先手动选择城市。")
    }
    private func finishRequest() {
        manager.stopUpdatingLocation();deadlineTimer?.invalidate();deadlineTimer=nil;deadline=nil
        phaseOfRequest = .idle
    }
    func cancelLocation() {
        finishRequest();wantsInitialFix=false;locationIssue=false
        status=coordinate == nil ? "定位已取消，可随时重试或手动选城市。" : "保留当前地点"
    }
    private func fail(_ message: String) { finishRequest();locationIssue=true;status=message }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { authorizationChanged(manager.authorizationStatus) }
    func authorizationChanged(_ value: CLAuthorizationStatus) {
        authorization=value
        if isAuthorized {
            if phaseOfRequest == .permission || wantsInitialFix {
                wantsInitialFix=false;beginUpdates()
            }
        } else if value == .denied || value == .restricted {
            if requesting { fail("定位未获允许。可打开系统定位设置，或手动选择城市。") }
        }
    }
    func locationManager(_ manager: CLLocationManager,didUpdateLocations locations: [CLLocation]) { receive(locations) }
    func receive(_ locations: [CLLocation]) {
        guard phaseOfRequest == .acquiring else { return }
        let current=now()
        guard let location=locations.filter({
            $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 50_000 &&
            abs($0.timestamp.timeIntervalSince(current)) <= 300 &&
            CLLocationCoordinate2DIsValid($0.coordinate)
        }).max(by:{$0.timestamp < $1.timestamp}) else { return }
        finishRequest();usesMacLocation=true;locationIssue=false;lastFixDate=location.timestamp
        preferences.removeObject(forKey:"solarManualLocation")
        applyLocation(latitude:location.coordinate.latitude,longitude:location.coordinate.longitude,name:"当前位置",timeZoneID:TimeZone.current.identifier)
        status="已取得 Mac 位置"
    }
    func locationManager(_ manager: CLLocationManager,didFailWithError error: Error) { receive(error:error) }
    func receive(error: Error) {
        guard requesting else { return }
        if let error=error as? CLError {
            switch error.code {
            case .locationUnknown:
                // This is transient for standard updates; leave our deadline armed.
                status="系统暂未确定位置，正在继续尝试…";return
            case .denied: authorization=manager.authorizationStatus;fail("系统定位服务未允许本次请求。请检查定位服务与 Winglight 权限。")
            case .network: fail("定位网络暂时不可用。请检查网络后重试，或手动选城市。")
            default: fail("系统定位失败（\(error.code.rawValue)），可重试或手动选城市。")
            }
        } else { fail("系统定位暂时不可用，可重试或手动选城市。") }
    }
    func openLocationSettings() {
        guard let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else { return }
        NSWorkspace.shared.open(url)
    }
    func setLocation(latitude: Double,longitude: Double,name: String,timeZoneID: String? = nil,persist: Bool = true) {
        guard latitude.isFinite,longitude.isFinite,abs(latitude)<=90,abs(longitude)<=180 else { status="请输入有效经纬度";return }
        finishRequest();wantsInitialFix=false;usesMacLocation=false;locationIssue=false;lastFixDate=nil
        applyLocation(latitude:latitude,longitude:longitude,name:name,timeZoneID:timeZoneID)
        if persist { preferences.set(["latitude":latitude,"longitude":longitude,"name":name,"timeZone":timeZone.identifier],forKey:"solarManualLocation") }
        status="使用手动地点"
    }
    private func applyLocation(latitude: Double,longitude: Double,name: String,timeZoneID: String? = nil) {
        guard latitude.isFinite,longitude.isFinite,abs(latitude)<=90,abs(longitude)<=180 else { return }
        if let timeZoneID,let zone=TimeZone(identifier:timeZoneID) { timeZone=zone }
        coordinate=CLLocationCoordinate2D(latitude:latitude,longitude:longitude);locationName=name;eventDay=nil
        refresh()
    }
    func refresh(at override: Date? = nil) {
        updateClock(date:override ?? manualDate ?? now(),manual:manualDate,returning:returningToNow)
    }
    private func updateClock(date newDate: Date,manual: Date?,returning: Bool) {
        // One coherent clock sample; never forward every field to the whole UI.
        objectWillChange.send()
        date=newDate;manualDate=manual;returningToNow=returning
        if let coordinate {
            position=Solar.position(at:date,latitude:coordinate.latitude,longitude:coordinate.longitude)
            let day=calendar.startOfDay(for:date)
            if eventDay != day { events=Solar.events(on:date,latitude:coordinate.latitude,longitude:coordinate.longitude,timeZone:timeZone);eventDay=day }
        }
        sceneChanges.send()
    }
    var hour: Double {
        let c=calendar.dateComponents([.hour,.minute,.second],from:date)
        return Double(c.hour ?? 0)+Double(c.minute ?? 0)/60+Double(c.second ?? 0)/3600
    }
    func previewHour(_ hour: Double) {
        guard hour.isFinite else { return }
        pendingHour=hour
        guard scrubTimer == nil else { return }
        isScrubbing=true
        // Coalesce high-frequency pointer events; the glass thumb follows the
        // pointer locally while the scene consumes at most one sample per frame.
        flushHour()
        let timer=Timer(timeInterval:1/60,repeats:true) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushHour() }
        }
        scrubTimer=timer;RunLoop.main.add(timer,forMode:.common)
    }
    private func flushHour() {
        if let hour=pendingHour { pendingHour=nil;setHour(hour) }
    }
    func endScrubbing() {
        flushHour();scrubTimer?.invalidate();scrubTimer=nil;isScrubbing=false;sceneChanges.send()
    }
    func setHour(_ hour: Double) {
        guard hour.isFinite else { return }
        timeTransition?.invalidate();timeTransition=nil
        if !followsClock { followsClock=true }
        let minute=Int(min(1439,max(0,(hour*60).rounded())))
        // Calendar wall time preserves DST rules, including non-24-hour days.
        guard let chosen=calendar.date(bySettingHour:minute/60,minute:minute%60,second:0,of:date) else { return }
        if date == chosen && manualDate != nil && !returningToNow { return }
        updateClock(date:chosen,manual:chosen,returning:false)
    }
    func restoreCurrentTime(animated: Bool = true) {
        endScrubbing();timeTransition?.invalidate();timeTransition=nil
        if !followsClock { followsClock=true }
        guard animated,manualDate != nil else { updateClock(date:now(),manual:nil,returning:false);return }
        let start=date,stamp=CACurrentMediaTime()
        updateClock(date:start,manual:start,returning:true)
        let timer=Timer(timeInterval:1/60,repeats:true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let t=min(1,(CACurrentMediaTime()-stamp)/0.85),ease=t*t*(3-2*t)
                let current=self.now(),sample=start.addingTimeInterval(current.timeIntervalSince(start)*ease)
                self.updateClock(date:t>=1 ? current : sample,manual:t>=1 ? nil : sample,returning:t<1)
                if t>=1 { self.timeTransition?.invalidate();self.timeTransition=nil }
            }
        }
        timeTransition=timer;RunLoop.main.add(timer,forMode:.common)
    }
    func clock(_ value: Date?) -> String {
        guard let value else { return "—" };return clockFormatter.string(from:value)
    }
    var phase: String {
        guard let position else { return "需要地点" }
        if position.elevation >= 0 { return "白天" }
        if position.elevation > -6 { return "曙暮光" }
        return "夜晚"
    }
}

import AppKit
import ScreenCaptureKit

// Record only Winglight's window; the desktop and other applications are excluded.
@available(macOS 15.0, *) final class Recording: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    var started=false
    var finished=false
    var error:Error?
    func recordingOutputDidStartRecording(_ recordingOutput:SCRecordingOutput) { started=true;print("RECORDING");fflush(stdout) }
    func recordingOutputDidFinishRecording(_ recordingOutput:SCRecordingOutput) { finished=true;print("FINISHED");fflush(stdout) }
    func recordingOutput(_ recordingOutput:SCRecordingOutput,didFailWithError error:Error) { self.error=error;finished=true }
}
@main struct CaptureDemo {
    @MainActor static func main() async throws {
        _=NSApplication.shared
        let args=CommandLine.arguments
        let content=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
        guard let window=content.windows.first(where:{$0.owningApplication?.bundleIdentifier=="local.winglight.simulator" && $0.frame.width>500}) else { throw NSError(domain:"No Winglight window",code:1) }
        let config=SCStreamConfiguration();config.width=Int(window.frame.width*2);config.height=Int(window.frame.height*2)
        config.minimumFrameInterval=CMTime(value:1,timescale:60);config.showsCursor=false;config.capturesAudio=false
        config.captureDynamicRange = .SDR;config.ignoreShadowsSingleWindow=true;config.captureResolution = .best
        let observer=Recording()
        let stream=SCStream(filter:SCContentFilter(desktopIndependentWindow:window),configuration:config,delegate:observer)
        let recordConfig=SCRecordingOutputConfiguration();recordConfig.outputURL=URL(fileURLWithPath:args[1]);recordConfig.videoCodecType = .h264;recordConfig.outputFileType = .mp4
        let output=SCRecordingOutput(configuration:recordConfig,delegate:observer)
        try stream.addRecordingOutput(output);try await stream.startCapture()
        try await Task.sleep(nanoseconds:UInt64((Double(args[2]) ?? 20)*1_000_000_000))
        try await stream.stopCapture()
        while !observer.finished { try await Task.sleep(nanoseconds:50_000_000) }
        if let error=observer.error { throw error }
    }
}

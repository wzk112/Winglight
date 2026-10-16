import AppKit
import ScreenCaptureKit
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

@main struct Capture {
    @MainActor static func main() async {
        _ = NSApplication.shared
        do {
            let args = CommandLine.arguments
            let out = args.count > 1 ? args[1] : "work/capture"
            let content = try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
            guard let window = content.windows.first(where:{$0.owningApplication?.bundleIdentifier == "local.winglight.simulator" && $0.frame.width > 500}) else { print("No Winglight window"); return }
            let filter = SCContentFilter(desktopIndependentWindow:window)
            let config = SCStreamConfiguration(preset:.captureHDRScreenshotLocalDisplay)
            config.width = Int(window.frame.width * 2)
            config.height = Int(window.frame.height * 2)
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            config.pixelFormat = kCVPixelFormatType_64RGBAHalf
            config.colorSpaceName = CGColorSpace.extendedLinearSRGB
            let image = try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
            guard let raw = image.dataProvider?.data else { return }
            let ptr = CFDataGetBytePtr(raw)!
            var maxValue: Float = 0, over = 0, peakX=0, peakY=0
            if image.bitsPerComponent == 16 {
                for y in 0..<image.height { for x in 0..<image.width {
                    let offset = y*image.bytesPerRow+x*8
                    let v = ptr.advanced(by:offset).withMemoryRebound(to:UInt16.self,capacity:4) { p in
                        max(Float(Float16(bitPattern:p[0])),max(Float(Float16(bitPattern:p[1])),Float(Float16(bitPattern:p[2]))))
                    }
                    if v > maxValue { maxValue = v; peakX=x; peakY=y }
                    if v > 1.001 { over += 1 }
                }}
            }
            let report: [String:Any] = ["windowTitle":window.title ?? "","bitsPerComponent":image.bitsPerComponent,"bitmapInfo":image.bitmapInfo.rawValue,"colorSpace":image.colorSpace?.name as String? ?? "unknown","compositedMaximumRGB":maxValue,"pixelsAboveSDR":over,"peakX":peakX,"peakY":peakY,"width":image.width,"height":image.height,"headroom":NSScreen.main?.maximumExtendedDynamicRangeColorComponentValue ?? 1]
            let json = try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
            try json.write(to:URL(fileURLWithPath:out+".json"))
            print(String(data:json,encoding:.utf8)!)
            config.captureDynamicRange = .SDR
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.colorSpaceName = CGColorSpace.sRGB
            let sdr = try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
            let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath:out+".png") as CFURL,UTType.png.identifier as CFString,1,nil)!
            CGImageDestinationAddImage(dest,sdr,nil); CGImageDestinationFinalize(dest)
        } catch { print("CAPTURE ERROR: \(error)") }
    }
}

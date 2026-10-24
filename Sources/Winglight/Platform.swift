import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum WinglightResources {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }
}

@MainActor enum WinglightPlatform {
    static var reduceMotion: Bool {
        #if os(macOS)
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        return UIAccessibility.isReduceMotionEnabled
        #endif
    }
    #if os(iOS)
    static let liveryCacheBudget = 128*1024*1024
    static let modelCacheBudget = 192*1024*1024
    #else
    static let liveryCacheBudget = 384*1024*1024
    static let modelCacheBudget = 384*1024*1024
    #endif
}

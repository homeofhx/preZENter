import Cocoa
import CoreGraphics

final class ContentSourceDiscovery {

    private let captureDeviceDiscovery = CaptureDeviceDiscovery()
    private let minimumWindowDimension: CGFloat = 125

    func discover() -> DiscoveredContentSources {
        let captureDevices = captureDeviceDiscovery.discover()
        return DiscoveredContentSources(windows: discoverWindows(),
                                        screens: discoverScreens(),
                                        videoDevices: captureDevices.video,
                                        iOSDevices: captureDevices.iOS)
    }

    private func discoverWindows() -> [WindowSource] {
        let options: CGWindowListOption = [.excludeDesktopElements, .optionOnScreenOnly]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: AnyObject]] else { return [] }

        return windowList.compactMap { window in
            guard let boundsDictionary = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  bounds.width >= minimumWindowDimension,
                  bounds.height >= minimumWindowDimension,
                  let windowTitle = window[kCGWindowName as String] as? String,
                  !windowTitle.isEmpty,
                  let applicationName = window[kCGWindowOwnerName as String] as? String,
                  applicationName != "preZENter",
                  let windowNumber = window[kCGWindowNumber as String] as? NSNumber else { return nil }

            return WindowSource(title: "\(applicationName): \(windowTitle)", windowID: windowNumber.uint32Value)
        }
    }

    private func discoverScreens() -> [ScreenSource] {
        return NSScreen.screens.compactMap { screen in
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }

            let title: String
            if #available(macOS 10.15, *) {
                title = screen.localizedName
            } else {
                title = "Screen: \(Int(screen.frame.width))x\(Int(screen.frame.height))"
            }

            return ScreenSource(title: title, displayID: displayID)
        }
    }

}

import CoreGraphics

enum ContentSourceKind: Equatable {
    case applicationWindow
    case screen
    case videoDevice
    case iOSDevice
}

enum ContentSource: Equatable {
    case applicationWindow(CGWindowID)
    case screen(CGDirectDisplayID)
    case videoDevice(String)
    case iOSDevice(String)

    var kind: ContentSourceKind {
        switch self {
        case .applicationWindow: return .applicationWindow
        case .screen: return .screen
        case .videoDevice: return .videoDevice
        case .iOSDevice: return .iOSDevice
        }
    }
}

struct WindowSource: Equatable {
    let title: String
    let windowID: CGWindowID

    var source: ContentSource { return .applicationWindow(windowID) }
}

struct ScreenSource: Equatable {
    let title: String
    let displayID: CGDirectDisplayID

    var source: ContentSource { return .screen(displayID) }
}

struct CaptureDeviceSource: Equatable {
    let name: String
    let uniqueID: String

    func source(kind: ContentSourceKind) -> ContentSource {
        switch kind {
        case .videoDevice: return .videoDevice(uniqueID)
        case .iOSDevice: return .iOSDevice(uniqueID)
        case .applicationWindow, .screen:
            preconditionFailure("Capture devices require a capture-device source kind")
        }
    }
}

struct DiscoveredContentSources {
    let windows: [WindowSource]
    let screens: [ScreenSource]
    let videoDevices: [CaptureDeviceSource]
    let iOSDevices: [CaptureDeviceSource]
}

struct ContentSourceCatalog {
    private(set) var windows: [WindowSource] = []
    private(set) var screens: [ScreenSource] = []
    private(set) var videoDevices: [CaptureDeviceSource] = []
    private(set) var iOSDevices: [CaptureDeviceSource] = []

    @discardableResult
    mutating func merge(_ discovered: DiscoveredContentSources) -> Bool {
        let mergedWindows = mergePreservingOrder(existing: windows, fresh: discovered.windows, key: { AnyHashable($0.windowID) })
        let mergedScreens = mergePreservingOrder(existing: screens, fresh: discovered.screens, key: { AnyHashable($0.displayID) })
        let mergedVideoDevices = mergePreservingOrder(existing: videoDevices, fresh: discovered.videoDevices, key: { AnyHashable($0.uniqueID) })
        let mergedIOSDevices = mergePreservingOrder(existing: iOSDevices, fresh: discovered.iOSDevices, key: { AnyHashable($0.uniqueID) })
        let didChange = mergedWindows != windows || mergedScreens != screens || mergedVideoDevices != videoDevices || mergedIOSDevices != iOSDevices

        windows = mergedWindows
        screens = mergedScreens
        videoDevices = mergedVideoDevices
        iOSDevices = mergedIOSDevices
        return didChange
    }

    func contains(_ source: ContentSource) -> Bool {
        return index(of: source) != nil
    }

    func title(for source: ContentSource) -> String? {
        switch source {
        case .applicationWindow(let windowID):
            return windows.first { $0.windowID == windowID }?.title
        case .screen(let displayID):
            return screens.first { $0.displayID == displayID }?.title
        case .videoDevice(let uniqueID):
            return videoDevices.first { $0.uniqueID == uniqueID }?.name
        case .iOSDevice(let uniqueID):
            return iOSDevices.first { $0.uniqueID == uniqueID }?.name
        }
    }

    func source(kind: ContentSourceKind, at index: Int) -> ContentSource? {
        guard index >= 0 else { return nil }

        switch kind {
        case .applicationWindow:
            guard windows.indices.contains(index) else { return nil }
            return windows[index].source
        case .screen:
            guard screens.indices.contains(index) else { return nil }
            return screens[index].source
        case .videoDevice:
            guard videoDevices.indices.contains(index) else { return nil }
            return videoDevices[index].source(kind: kind)
        case .iOSDevice:
            guard iOSDevices.indices.contains(index) else { return nil }
            return iOSDevices[index].source(kind: kind)
        }
    }

    func index(of source: ContentSource) -> Int? {
        switch source {
        case .applicationWindow(let windowID):
            return windows.firstIndex { $0.windowID == windowID }
        case .screen(let displayID):
            return screens.firstIndex { $0.displayID == displayID }
        case .videoDevice(let uniqueID):
            return videoDevices.firstIndex { $0.uniqueID == uniqueID }
        case .iOSDevice(let uniqueID):
            return iOSDevices.firstIndex { $0.uniqueID == uniqueID }
        }
    }

    private func mergePreservingOrder<T>(existing: [T], fresh: [T], key: (T) -> AnyHashable) -> [T] {
        let freshByKey = Dictionary(fresh.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
        let stillPresent = existing.compactMap { freshByKey[key($0)] }
        let stillPresentKeys = Set(stillPresent.map(key))
        let newItems = fresh.filter { !stillPresentKeys.contains(key($0)) }
        return newItems + stillPresent
    }
}

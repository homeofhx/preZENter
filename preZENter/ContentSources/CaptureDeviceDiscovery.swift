import AVFoundation
import CoreMediaIO

final class CaptureDeviceDiscovery {
    typealias DeviceLists = (video: [CaptureDeviceSource], iOS: [CaptureDeviceSource])

    private static let iOSScreenCapturePluginID = "com.apple.cmio.DAL.iOSScreenCapture"
    private static let iOSScreenCaptureModelID = "iOS Device"

    init() {
        CaptureDeviceDiscovery.enableIOSScreenCaptureDevices()
    }

    func discover() -> DeviceLists {
        CaptureDeviceDiscovery.enableIOSScreenCaptureDevices()
        let iOSDeviceIDs = CaptureDeviceDiscovery.iOSScreenCaptureDeviceIDs()
        var videoDevices: [CaptureDeviceSource] = []
        var iOSDevices: [CaptureDeviceSource] = []

        for device in CaptureDeviceDiscovery.enumerateCaptureDevices() {
            let source = CaptureDeviceSource(name: device.localizedName, uniqueID: device.uniqueID)
            if iOSDeviceIDs.contains(device.uniqueID) ||
                device.modelID.caseInsensitiveCompare(CaptureDeviceDiscovery.iOSScreenCaptureModelID) == .orderedSame {
                iOSDevices.append(source)
            } else {
                videoDevices.append(source)
            }
        }

        return (video: videoDevices, iOS: iOSDevices)
    }

    static func matchingAudioDevice(for device: AVCaptureDevice) -> AVCaptureDevice? {
        let audioDevices = AVCaptureDevice.devices(for: .audio)

        if let linkedUID = linkedAudioDeviceUID(for: device.uniqueID),
           let linkedDevice = audioDevices.first(where: { $0.uniqueID == linkedUID }) {
            return linkedDevice
        }

        return audioDevices.first { $0.localizedName == device.localizedName }
    }

    private static func enumerateCaptureDevices() -> [AVCaptureDevice] {
        var seen = Set<String>()
        return (AVCaptureDevice.devices(for: .video) + AVCaptureDevice.devices(for: .muxed))
            .filter { $0.isConnected && seen.insert($0.uniqueID).inserted }
    }

    private static func enableIOSScreenCaptureDevices() {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMaster))
        var allow: UInt32 = 1

        CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &allow)
    }

    private static func iOSScreenCaptureDeviceIDs() -> Set<String> {
        return Set(cmioDeviceIDs().compactMap { deviceID in
            guard let creator = stringProperty(CMIOObjectPropertySelector(kCMIOObjectPropertyCreator), on: deviceID),
                  creator == iOSScreenCapturePluginID else { return nil }
            return stringProperty(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID), on: deviceID)
        })
    }

    private static func linkedAudioDeviceUID(for captureDeviceUID: String) -> String? {
        guard let deviceID = cmioDeviceIDs().first(where: {
            stringProperty(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID), on: $0) == captureDeviceUID
        }) else { return nil }

        return stringProperty(CMIOObjectPropertySelector(kCMIODevicePropertyLinkedAndSyncedCoreAudioDeviceUID), on: deviceID)
            ?? stringProperty(CMIOObjectPropertySelector(kCMIODevicePropertyLinkedCoreAudioDeviceUID), on: deviceID)
    }

    private static func cmioDeviceIDs() -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMaster))
        var dataSize: UInt32 = 0

        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var deviceIDs = [CMIOObjectID](repeating: 0, count: count)
        var dataUsed: UInt32 = 0
        let status = deviceIDs.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return OSStatus(-1) }
            return CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, dataSize, &dataUsed, baseAddress)
        }

        return status == noErr ? deviceIDs : []
    }

    private static func stringProperty(_ selector: CMIOObjectPropertySelector, on objectID: CMIOObjectID) -> String? {
        var address = CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMaster))
        guard CMIOObjectHasProperty(objectID, &address) else { return nil }

        var value: Unmanaged<CFString>?
        let dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var dataUsed: UInt32 = 0
        guard CMIOObjectGetPropertyData(objectID, &address, 0, nil, dataSize, &dataUsed, &value) == noErr,
              let string = value?.takeRetainedValue() else { return nil }
        
        return string as String
    }

}

import AVFoundation
import CoreMediaIO

final class CaptureDevDiscovery {
    
    typealias DeviceItem = (name: String, uniqueID: String)
    typealias DeviceLists = (video: [DeviceItem], iOS: [DeviceItem])
    
    private static let iOSScreenCapturePluginID = "com.apple.cmio.DAL.iOSScreenCapture"
    private static let iOSScreenCaptureModelID = "iOS Device"
    
    init() {
        CaptureDevDiscovery.enableIOSScreenCaptureDevices()
    }
    
    func getDeviceLists() -> DeviceLists {
        CaptureDevDiscovery.enableIOSScreenCaptureDevices()
        let iOSDeviceIDs = CaptureDevDiscovery.iOSScreenCaptureDeviceIDs()
        let devices = CaptureDevDiscovery.enumerateAllCaptureDevices()
        var videoItems: [DeviceItem] = []
        var iOSItems: [DeviceItem] = []
        
        for device in devices {
            let item = (name: device.localizedName, uniqueID: device.uniqueID)
            if iOSDeviceIDs.contains(device.uniqueID) ||
                device.modelID.caseInsensitiveCompare(CaptureDevDiscovery.iOSScreenCaptureModelID) == .orderedSame {
                iOSItems.append(item)
            } else {
                videoItems.append(item)
            }
        }
        
        return (video: videoItems, iOS: iOSItems)
    }
    
    static func matchingAudioDevice(for device: AVCaptureDevice) -> AVCaptureDevice? {
        let audioDevices = AVCaptureDevice.devices(for: .audio)
        
        if let linkedUID = linkedAudioDeviceUID(for: device.uniqueID),
           let linkedDevice = audioDevices.first(where: { $0.uniqueID == linkedUID }) {
            return linkedDevice
        }
        
        return audioDevices.first { $0.localizedName == device.localizedName }
    }
    
    private static func enumerateAllCaptureDevices() -> [AVCaptureDevice] {
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
        
        CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject),
                                  &address,
                                  0,
                                  nil,
                                  UInt32(MemoryLayout<UInt32>.size),
                                  &allow)
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
        
        return stringProperty(CMIOObjectPropertySelector(kCMIODevicePropertyLinkedAndSyncedCoreAudioDeviceUID),
                              on: deviceID)
            ?? stringProperty(CMIOObjectPropertySelector(kCMIODevicePropertyLinkedCoreAudioDeviceUID),
                              on: deviceID)
    }
    
    private static func cmioDeviceIDs() -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMaster))
        var dataSize: UInt32 = 0
        
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject),
                                            &address,
                                            0,
                                            nil,
                                            &dataSize) == noErr,
              dataSize > 0 else { return [] }
        
        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var deviceIDs = [CMIOObjectID](repeating: 0, count: count)
        var dataUsed: UInt32 = 0
        let status = deviceIDs.withUnsafeMutableBufferPointer { buffer in
            CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject),
                                      &address,
                                      0,
                                      nil,
                                      dataSize,
                                      &dataUsed,
                                      buffer.baseAddress!)
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
        guard CMIOObjectGetPropertyData(objectID,
                                        &address,
                                        0,
                                        nil,
                                        dataSize,
                                        &dataUsed,
                                        &value) == noErr,
              let string = value?.takeRetainedValue() else { return nil }
        return string as String
    }
    
}

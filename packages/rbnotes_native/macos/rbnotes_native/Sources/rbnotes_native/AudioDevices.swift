import CoreAudio
import Foundation

/// Enumerates CoreAudio input devices and resolves a device UID back to an
/// `AudioDeviceID` for `AVAudioEngine`'s input node.
enum AudioDevices {
  /// Input devices as channel-map dictionaries `{id, name, isDefault}`.
  /// `id` is the stable device UID.
  static func inputDevices() -> [[String: Any]] {
    let defaultId = defaultInputDeviceID()
    var result: [[String: Any]] = []
    for device in allDeviceIDs() where inputChannelCount(device) > 0 {
      guard let uid = stringProperty(device, kAudioDevicePropertyDeviceUID) else { continue }
      let name = stringProperty(device, kAudioObjectPropertyName)
        ?? stringProperty(device, kAudioDevicePropertyDeviceNameCFString)
        ?? uid
      result.append([
        "id": uid,
        "name": name,
        "isDefault": device == defaultId,
      ])
    }
    return result
  }

  /// Resolves a device UID to its current `AudioDeviceID`, or nil if the UID is
  /// unknown (e.g. the device was unplugged).
  static func resolve(uid: String) -> AudioDeviceID? {
    for device in allDeviceIDs()
    where stringProperty(device, kAudioDevicePropertyDeviceUID) == uid {
      return device
    }
    return nil
  }

  // MARK: - CoreAudio plumbing

  private static func allDeviceIDs() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var dataSize: UInt32 = 0
    guard
      AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr
    else { return [] }
    let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    guard count > 0 else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: count)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids) == noErr
    else { return [] }
    return ids
  }

  private static func defaultInputDeviceID() -> AudioDeviceID? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var deviceId = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceId) == noErr,
      deviceId != 0
    else { return nil }
    return deviceId
  }

  private static func inputChannelCount(_ device: AudioDeviceID) -> Int {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreamConfiguration,
      mScope: kAudioObjectPropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain)
    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &dataSize) == noErr,
      dataSize > 0
    else { return 0 }
    let bufferList = UnsafeMutableRawPointer.allocate(
      byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { bufferList.deallocate() }
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &dataSize, bufferList) == noErr
    else { return 0 }
    let abl = UnsafeMutableAudioBufferListPointer(
      bufferList.assumingMemoryBound(to: AudioBufferList.self))
    var channels = 0
    for buffer in abl { channels += Int(buffer.mNumberChannels) }
    return channels
  }

  private static func stringProperty(
    _ device: AudioDeviceID, _ selector: AudioObjectPropertySelector
  ) -> String? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var cfString: CFString? = nil
    var size = UInt32(MemoryLayout<CFString?>.size)
    let status = withUnsafeMutablePointer(to: &cfString) { ptr -> OSStatus in
      AudioObjectGetPropertyData(device, &address, 0, nil, &size, ptr)
    }
    guard status == noErr, let cfString else { return nil }
    return cfString as String
  }
}

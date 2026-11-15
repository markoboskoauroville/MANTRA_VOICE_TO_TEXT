// v28 (Marko, 15.11.2026: "two drop-down menus, input and output. Input is which microphone, output is which speaker."):
// INPUT is InputDevice (Hands.swift, the microphone a take records from). OUTPUT is the speaker of Vox's own sounds: the
// start and stop sounds and the magnet's pop (NSSound.playbackDeviceIdentifier). The system's default output is never
// changed here (the duck still lowers the default output while listening, as before).
import AppKit
import CoreAudio
import AVFoundation

enum OutputDevice {
    /// the CoreAudio UID chosen in Settings; nil = the system's default output
    static var chosenUID: String? {
        get { UserDefaults.standard.string(forKey: "outputDevice") }
        set { UserDefaults.standard.set(newValue, forKey: "outputDevice") }
    }

    /// every device with output channels: (UID, name)
    static func all() -> [(String, String)] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        var out: [(String, String)] = []
        for id in ids {
            var sAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput,
                                                   mElement: kAudioObjectPropertyElementMain)
            var sSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &sAddr, 0, nil, &sSize) == noErr, sSize > 0 else { continue }
            guard let uid = string(id, kAudioDevicePropertyDeviceUID), let name = string(id, kAudioObjectPropertyName) else { continue }
            out.append((uid, name))
        }
        return out
    }

    static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let v = value else { return nil }
        return v.takeRetainedValue() as String
    }

    /// the default output's name, for "System default (...)"
    static func defaultName() -> String {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else { return "none" }
        return string(id, kAudioObjectPropertyName) ?? "none"
    }

    /// a Vox sound to the chosen speaker (one that is no longer plugged in: the system default)
    static func apply(_ s: NSSound?) {
        guard let s, let uid = chosenUID, all().contains(where: { $0.0 == uid }) else { return }
        s.playbackDeviceIdentifier = uid          // a plain String typealias
    }

    /// devices plugged in or out: `changed` on the main thread
    static func watch(_ changed: @escaping () -> Void) {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main) { _, _ in changed() }
        for n in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { _ in changed() }
        }
    }
}

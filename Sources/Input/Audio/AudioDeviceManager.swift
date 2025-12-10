//
//  AudioDeviceManager.swift
//  OnesecCore
//

import AVFoundation
import CoreAudio

struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let uid: String

    var isDefault: Bool {
        id == AudioDeviceManager.shared.defaultInputDeviceID
    }
}

class AudioDeviceManager {
    static let shared = AudioDeviceManager()

    private(set) var inputDevices: [AudioDevice] = []
    private(set) var defaultInputDeviceID: AudioDeviceID = 0

    var selectedDeviceID: AudioDeviceID? {
        get {
            let saved = UserDefaults.standard.integer(forKey: "selectedAudioDeviceID")
            return saved > 0 ? AudioDeviceID(saved) : nil
        }
        set {
            if let id = newValue {
                UserDefaults.standard.set(Int(id), forKey: "selectedAudioDeviceID")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedAudioDeviceID")
            }
            applySelectedDevice()
        }
    }

    private init() {
        refreshDevices()
        setupDeviceChangeListener()
    }

    private func setupDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            { _, _, _, _ in
                Task { @MainActor in
                    AudioDeviceManager.shared.handleDeviceChange()
                }
                return noErr
            },
            nil
        )
    }

    private func handleDeviceChange() {
        let oldDefault = defaultInputDeviceID
        refreshDevices()
        if oldDefault != defaultInputDeviceID {
            log.info("🎧 Input Device Changed: \(getDeviceName(defaultInputDeviceID) ?? "Unknown")".yellow)
            ConnectionCenter.shared.resetInputService()
        }
    }

    func refreshDevices() {
        defaultInputDeviceID = getDefaultInputDeviceID()
        inputDevices = getInputDevices()
    }

    private func getDefaultInputDeviceID() -> AudioDeviceID {
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }

    private func getInputDevices() -> [AudioDevice] {
        var devices: [AudioDevice] = []

        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return devices
        }

        let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs) == noErr else {
            return devices
        }

        for deviceID in deviceIDs {
            if hasInputChannels(deviceID),
               !isAggregateDevice(deviceID),
               let name = getDeviceName(deviceID),
               let uid = getDeviceUID(deviceID)
            {
                devices.append(AudioDevice(id: deviceID, name: name, uid: uid))
            }
        }

        return devices
    }

    // 这是 macOS 系统创建的聚合设备（Aggregate Device）
    // 通常由系统或某些应用自动生成，用于组合多个音频设备。不是真正的物理设备
    private func isAggregateDevice(_ deviceID: AudioDeviceID) -> Bool {
        var transportType: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transportType) == noErr else {
            return false
        }
        return transportType == kAudioDeviceTransportTypeAggregate
    }

    private func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else {
            return false
        }

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { bufferList.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferList) == noErr else {
            return false
        }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name) == noErr,
              let cfName = name?.takeUnretainedValue()
        else {
            return nil
        }
        return cfName as String
    }

    private func getDeviceUID(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid) == noErr,
              let cfUID = uid?.takeUnretainedValue()
        else {
            return nil
        }
        return cfUID as String
    }

    func applySelectedDevice() {
        guard let deviceID = selectedDeviceID else { return }
        setSystemInputDevice(deviceID)
    }

    private func setSystemInputDevice(_ deviceID: AudioDeviceID) {
        var mutableDeviceID = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let result = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &mutableDeviceID)
        if result == noErr {
            // log.info("🎧 Input Device Changed: \(getDeviceName(defaultInputDeviceID) ?? "Unknown")".yellow)
            // ConnectionCenter.shared.resetInputService()
        } else {
            log.error("Failed to change audio input device: \(result)")
        }
    }
}

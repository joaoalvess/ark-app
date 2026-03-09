import Foundation
import CoreAudio

final class AggregateDeviceManager: @unchecked Sendable {
    private var aggregateDeviceID: AudioDeviceID = 0
    private let lock = NSLock()

    // MARK: - Create / Destroy

    func createAggregateDevice(blackHoleDeviceID: AudioDeviceID) throws {
        let defaultOutputUID = try currentDefaultOutputUID()
        guard let blackHoleUID = deviceUID(for: blackHoleDeviceID) else {
            throw AggregateError.blackHoleUIDNotFound
        }

        let subDevices: [[String: Any]] = [
            [kAudioSubDeviceUIDKey: defaultOutputUID],
            [
                kAudioSubDeviceUIDKey: blackHoleUID,
                kAudioSubDeviceDriftCompensationKey: true
            ]
        ]

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: Constants.AudioDriver.AGGREGATE_DEVICE_NAME,
            kAudioAggregateDeviceUIDKey: Constants.AudioDriver.AGGREGATE_DEVICE_UID,
            kAudioAggregateDeviceSubDeviceListKey: subDevices,
            kAudioAggregateDeviceMasterSubDeviceKey: defaultOutputUID,
            kAudioAggregateDeviceIsPrivateKey: true
        ]

        var deviceID: AudioDeviceID = 0
        let result = AudioHardwareCreateAggregateDevice(description as CFDictionary, &deviceID)
        guard result == noErr else {
            throw AggregateError.creationFailed(result)
        }

        lock.withLock { aggregateDeviceID = deviceID }
    }

    func destroyAggregateDevice() {
        let deviceID = lock.withLock { aggregateDeviceID }
        guard deviceID != 0 else { return }
        AudioHardwareDestroyAggregateDevice(deviceID)
        lock.withLock { aggregateDeviceID = 0 }
    }

    // MARK: - System Output

    func activateAsSystemOutput() throws {
        let deviceID = lock.withLock { aggregateDeviceID }
        guard deviceID != 0 else { throw AggregateError.noAggregateDevice }

        // Save original output UID for crash safety (only if not already saved)
        if UserDefaults.standard.string(forKey: Constants.AudioDriver.ORIGINAL_OUTPUT_UID_KEY) == nil {
            let originalUID = try currentDefaultOutputUID()
            UserDefaults.standard.set(originalUID, forKey: Constants.AudioDriver.ORIGINAL_OUTPUT_UID_KEY)
        }

        try setDefaultOutputDevice(deviceID)
    }

    func restoreOriginalOutput() {
        guard let savedUID = UserDefaults.standard.string(
            forKey: Constants.AudioDriver.ORIGINAL_OUTPUT_UID_KEY
        ) else { return }

        if let deviceID = deviceIDFromUID(savedUID) {
            try? setDefaultOutputDevice(deviceID)
        }

        UserDefaults.standard.removeObject(forKey: Constants.AudioDriver.ORIGINAL_OUTPUT_UID_KEY)
    }

    func cleanup() {
        restoreOriginalOutput()
        destroyAggregateDevice()
    }

    /// Called on app launch to restore output if previous session crashed
    func restoreIfNeeded() {
        guard UserDefaults.standard.string(
            forKey: Constants.AudioDriver.ORIGINAL_OUTPUT_UID_KEY
        ) != nil else { return }
        restoreOriginalOutput()
    }

    // MARK: - Private

    private func currentDefaultOutputUID() throws -> String {
        var propAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propAddress, 0, nil, &size, &deviceID
        )
        guard result == noErr else {
            throw AggregateError.defaultOutputNotFound
        }

        guard let uid = deviceUID(for: deviceID) else {
            throw AggregateError.defaultOutputNotFound
        }
        return uid
    }

    private func setDefaultOutputDevice(_ deviceID: AudioDeviceID) throws {
        var propAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var mutableDeviceID = deviceID
        let result = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propAddress, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &mutableDeviceID
        )
        guard result == noErr else {
            throw AggregateError.setOutputFailed(result)
        }
    }

    private func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var propAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let result = AudioObjectGetPropertyData(
            deviceID, &propAddress, 0, nil, &dataSize, &uid
        )
        guard result == noErr else { return nil }
        return uid?.takeUnretainedValue() as String?
    }

    private func deviceIDFromUID(_ uid: String) -> AudioDeviceID? {
        var propAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var cfUID: CFString = uid as CFString
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let result = withUnsafeMutablePointer(to: &cfUID) { uidPtr in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propAddress, UInt32(MemoryLayout<CFString>.size), uidPtr,
                &size, &deviceID
            )
        }
        guard result == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    // MARK: - Errors

    enum AggregateError: LocalizedError {
        case blackHoleUIDNotFound
        case creationFailed(OSStatus)
        case noAggregateDevice
        case defaultOutputNotFound
        case setOutputFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .blackHoleUIDNotFound: "UID do dispositivo BlackHole nao encontrado."
            case .creationFailed(let s): "Falha ao criar dispositivo agregado (erro \(s))."
            case .noAggregateDevice: "Dispositivo agregado nao existe."
            case .defaultOutputNotFound: "Dispositivo de saida padrao nao encontrado."
            case .setOutputFailed(let s): "Falha ao definir saida de audio (erro \(s))."
            }
        }
    }
}

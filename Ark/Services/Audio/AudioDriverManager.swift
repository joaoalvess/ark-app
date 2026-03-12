import Foundation
import CoreAudio
import AppKit
import Observation

@MainActor @Observable
final class AudioDriverManager {
    private(set) var status: DriverStatus = .notInstalled

    enum DriverStatus: Equatable {
        case notInstalled
        case installed
        case installing
        case needsRestart
        case error(String)
    }

    enum DriverError: LocalizedError {
        case packageNotFound
        case installationFailed
        case deviceNotFound

        var errorDescription: String? {
            switch self {
            case .packageNotFound: "Audio driver package not found in the app resources."
            case .installationFailed: "Failed to install the audio driver."
            case .deviceNotFound: "BlackHole device not found. Restart your computer after installation."
            }
        }
    }

    func checkInstallation() {
        if findBlackHoleDeviceID() != nil {
            status = .installed
        } else if FileManager.default.fileExists(atPath: Constants.AudioDriver.DRIVER_HAL_PATH) {
            status = .needsRestart
        } else {
            status = .notInstalled
        }
    }

    nonisolated func findBlackHoleDeviceID() -> AudioDeviceID? {
        var propAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var result = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propAddress, 0, nil, &dataSize
        )
        guard result == noErr else { return nil }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propAddress, 0, nil, &dataSize, &devices
        )
        guard result == noErr else { return nil }

        for deviceID in devices {
            guard let uid = deviceUID(for: deviceID) else { continue }
            if uid.contains(Constants.AudioDriver.BLACKHOLE_UID_SUBSTRING) {
                return deviceID
            }
        }

        return nil
    }

    func installDriver() {
        guard let pkgURL = Bundle.main.url(
            forResource: Constants.AudioDriver.PKG_RESOURCE_NAME,
            withExtension: Constants.AudioDriver.PKG_RESOURCE_EXT
        ) else {
            status = .error(DriverError.packageNotFound.localizedDescription)
            return
        }

        status = .installing
        NSWorkspace.shared.open(pkgURL)
    }

    // MARK: - Private

    private nonisolated func deviceUID(for deviceID: AudioDeviceID) -> String? {
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
}

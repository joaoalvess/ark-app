import AppKit
import CoreAudio
import Foundation
import Observation

struct AudioDeviceSnapshot: Equatable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

struct AudioOutputSubdeviceSnapshot: Equatable, Sendable {
    let uid: String
    let name: String
    let driftCompensationEnabled: Bool?
}

struct AudioOutputRoutingSnapshot: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case direct
        case aggregate
    }

    let output: AudioDeviceSnapshot
    let kind: Kind
    let subdevices: [AudioOutputSubdeviceSnapshot]
    let mainSubdeviceUID: String?
    let clockDeviceUID: String?

    func subdevice(uid: String) -> AudioOutputSubdeviceSnapshot? {
        subdevices.first(where: { $0.uid == uid })
    }
}

protocol AudioHardwareInspecting {
    func allDevices() -> [AudioDeviceSnapshot]
    func defaultOutputDevice() -> AudioDeviceSnapshot?
    func outputRoutingSnapshot(for device: AudioDeviceSnapshot) -> AudioOutputRoutingSnapshot?
    func fileExists(atPath path: String) -> Bool
}

protocol AudioDriverValidationStoring {
    var validatedOutputUID: String? { get set }
    var validatedDriverUID: String? { get set }
}

struct CoreAudioHardwareInspector: AudioHardwareInspecting {
    func allDevices() -> [AudioDeviceSnapshot] {
        var propAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeResult = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propAddress, 0, nil, &dataSize
        )
        guard sizeResult == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        let dataResult = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propAddress, 0, nil, &dataSize, &deviceIDs
        )
        guard dataResult == noErr else { return [] }

        return deviceIDs.compactMap { deviceID in
            guard let uid = deviceUID(for: deviceID), let name = deviceName(for: deviceID) else {
                return nil
            }
            return AudioDeviceSnapshot(id: deviceID, uid: uid, name: name)
        }
    }

    func defaultOutputDevice() -> AudioDeviceSnapshot? {
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
        guard result == noErr,
              let uid = deviceUID(for: deviceID),
              let name = deviceName(for: deviceID) else {
            return nil
        }

        return AudioDeviceSnapshot(id: deviceID, uid: uid, name: name)
    }

    func outputRoutingSnapshot(for device: AudioDeviceSnapshot) -> AudioOutputRoutingSnapshot? {
        let isAggregate = readClassProperty(for: device.id) == kAudioAggregateDeviceClassID ||
            hasProperty(selector: kAudioAggregateDevicePropertyComposition, deviceID: device.id) ||
            hasProperty(selector: kAudioAggregateDevicePropertyFullSubDeviceList, deviceID: device.id)

        guard isAggregate else {
            return AudioOutputRoutingSnapshot(
                output: device,
                kind: .direct,
                subdevices: [],
                mainSubdeviceUID: nil,
                clockDeviceUID: nil
            )
        }

        let namesByUID = Dictionary(uniqueKeysWithValues: allDevices().map { ($0.uid, $0.name) })
        let orderedUIDs = readStringArrayProperty(
            selector: kAudioAggregateDevicePropertyFullSubDeviceList,
            deviceID: device.id
        ) ?? []
        let mainSubdeviceUID = readStringProperty(
            selector: kAudioAggregateDevicePropertyMainSubDevice,
            deviceID: device.id
        )
        let clockDeviceUID = readStringProperty(
            selector: kAudioAggregateDevicePropertyClockDevice,
            deviceID: device.id
        )

        let composition = readDictionaryProperty(
            selector: kAudioAggregateDevicePropertyComposition,
            deviceID: device.id
        )
        let compositionEntries = parseAggregateSubdevices(from: composition)
        let compositionByUID = Dictionary(uniqueKeysWithValues: compositionEntries.map { ($0.uid, $0) })

        var allUIDs = orderedUIDs
        for entry in compositionEntries where !allUIDs.contains(entry.uid) {
            allUIDs.append(entry.uid)
        }

        let subdevices = allUIDs.map { uid in
            let compositionEntry = compositionByUID[uid]
            return AudioOutputSubdeviceSnapshot(
                uid: uid,
                name: compositionEntry?.name ?? namesByUID[uid] ?? uid,
                driftCompensationEnabled: compositionEntry?.driftCompensationEnabled
            )
        }

        return AudioOutputRoutingSnapshot(
            output: device,
            kind: .aggregate,
            subdevices: subdevices,
            mainSubdeviceUID: mainSubdeviceUID,
            clockDeviceUID: clockDeviceUID
        )
    }

    func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    private func hasProperty(selector: AudioObjectPropertySelector, deviceID: AudioDeviceID) -> Bool {
        var propAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectHasProperty(deviceID, &propAddress)
    }

    private func readClassProperty(for deviceID: AudioDeviceID) -> AudioClassID? {
        var propAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyClass,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var classID: AudioClassID = 0
        var dataSize = UInt32(MemoryLayout<AudioClassID>.size)
        let result = AudioObjectGetPropertyData(
            deviceID, &propAddress, 0, nil, &dataSize, &classID
        )
        guard result == noErr else { return nil }
        return classID
    }

    private func deviceUID(for deviceID: AudioDeviceID) -> String? {
        readStringProperty(
            selector: kAudioDevicePropertyDeviceUID,
            deviceID: deviceID
        )
    }

    private func deviceName(for deviceID: AudioDeviceID) -> String? {
        readStringProperty(
            selector: kAudioObjectPropertyName,
            deviceID: deviceID
        )
    }

    private func readStringProperty(selector: AudioObjectPropertySelector, deviceID: AudioDeviceID) -> String? {
        var propAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let result = AudioObjectGetPropertyData(
            deviceID, &propAddress, 0, nil, &dataSize, &value
        )
        guard result == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private func readStringArrayProperty(selector: AudioObjectPropertySelector, deviceID: AudioDeviceID) -> [String]? {
        var propAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var value: Unmanaged<CFArray>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFArray>?>.size)
        let result = AudioObjectGetPropertyData(
            deviceID, &propAddress, 0, nil, &dataSize, &value
        )
        guard result == noErr,
              let array = value?.takeRetainedValue() as? [String] else {
            return nil
        }
        return array
    }

    private func readDictionaryProperty(selector: AudioObjectPropertySelector, deviceID: AudioDeviceID) -> [String: Any]? {
        var propAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var value: Unmanaged<CFDictionary>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFDictionary>?>.size)
        let result = AudioObjectGetPropertyData(
            deviceID, &propAddress, 0, nil, &dataSize, &value
        )
        guard result == noErr,
              let dictionary = value?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    private func parseAggregateSubdevices(from composition: [String: Any]?) -> [AggregateSubdeviceCompositionEntry] {
        let subdeviceListKey = String(cString: kAudioAggregateDeviceSubDeviceListKey)
        let subdeviceUIDKey = String(cString: kAudioSubDeviceUIDKey)
        let subdeviceNameKey = String(cString: kAudioSubDeviceNameKey)
        let driftKey = String(cString: kAudioSubDeviceDriftCompensationKey)

        guard let rawEntries = composition?[subdeviceListKey] as? [[String: Any]] else {
            return []
        }

        return rawEntries.compactMap { entry in
            guard let uid = entry[subdeviceUIDKey] as? String else { return nil }
            let name = entry[subdeviceNameKey] as? String
            let driftCompensationEnabled = (entry[driftKey] as? NSNumber).map { $0.intValue != 0 }
            return AggregateSubdeviceCompositionEntry(
                uid: uid,
                name: name,
                driftCompensationEnabled: driftCompensationEnabled
            )
        }
    }
}

private struct AggregateSubdeviceCompositionEntry {
    let uid: String
    let name: String?
    let driftCompensationEnabled: Bool?
}

struct UserDefaultsAudioDriverValidationStore: AudioDriverValidationStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var validatedOutputUID: String? {
        get { defaults.string(forKey: Constants.AudioDriver.ROUTING_VALIDATED_OUTPUT_UID_KEY) }
        set { defaults.set(newValue, forKey: Constants.AudioDriver.ROUTING_VALIDATED_OUTPUT_UID_KEY) }
    }

    var validatedDriverUID: String? {
        get { defaults.string(forKey: Constants.AudioDriver.ROUTING_VALIDATED_DRIVER_UID_KEY) }
        set { defaults.set(newValue, forKey: Constants.AudioDriver.ROUTING_VALIDATED_DRIVER_UID_KEY) }
    }
}

@MainActor @Observable
final class AudioDriverManager {
    private let hardwareInspector: AudioHardwareInspecting
    private var validationStore: AudioDriverValidationStoring

    private(set) var status: DriverStatus = .notInstalled
    private(set) var statusDetail = "Instale o ArkAudio para capturar o áudio do sistema."
    private(set) var detectedDriver: AudioDeviceSnapshot?
    private(set) var defaultOutput: AudioDeviceSnapshot?
    private(set) var defaultOutputRouting: AudioOutputRoutingSnapshot?

    enum DriverStatus: Equatable {
        case notInstalled
        case installing
        case needsRestart
        case legacyDriverInstalled
        case routingNotVerified
        case installed
        case error(String)
    }

    enum DriverError: LocalizedError {
        case packageNotFound
        case installationFailed
        case deviceNotFound

        var errorDescription: String? {
            switch self {
            case .packageNotFound: "O instalador do ArkAudio não foi encontrado nos recursos do app."
            case .installationFailed: "Falha ao iniciar a instalação do ArkAudio."
            case .deviceNotFound: "O ArkAudio não apareceu no sistema. Reinicie o Mac após instalar."
            }
        }
    }

    init(
        hardwareInspector: AudioHardwareInspecting = CoreAudioHardwareInspector(),
        validationStore: AudioDriverValidationStoring = UserDefaultsAudioDriverValidationStore()
    ) {
        self.hardwareInspector = hardwareInspector
        self.validationStore = validationStore
    }

    var currentOutputName: String {
        defaultOutput?.name ?? "Desconhecida"
    }

    func checkInstallation() {
        let devices = hardwareInspector.allDevices()
        let arkDevice = devices.first(where: { $0.uid.contains(Constants.AudioDriver.DEVICE_UID_SUBSTRING) })
        let legacyInstalled = hasLegacyBlackHole(installedDevices: devices)

        detectedDriver = arkDevice
        defaultOutput = hardwareInspector.defaultOutputDevice()
        defaultOutputRouting = defaultOutput.flatMap { hardwareInspector.outputRoutingSnapshot(for: $0) }

        if let arkDevice {
            updateStatusForInstalledDriver(arkDevice)
            return
        }

        if hardwareInspector.fileExists(atPath: Constants.AudioDriver.DRIVER_HAL_PATH) {
            status = .needsRestart
            statusDetail = "O ArkAudio foi instalado em disco, mas o macOS ainda não carregou o driver."
            return
        }

        if legacyInstalled {
            status = .legacyDriverInstalled
            statusDetail = "Há um BlackHole legado instalado. O Ark agora usa o fork ArkAudio."
            return
        }

        status = .notInstalled
        statusDetail = "Instale o ArkAudio para habilitar a captura do áudio do sistema."
    }

    func installDriver() {
        guard let pkgURL = Bundle.main.url(
            forResource: Constants.AudioDriver.PKG_RESOURCE_NAME,
            withExtension: Constants.AudioDriver.PKG_RESOURCE_EXT
        ) else {
            status = .error(DriverError.packageNotFound.localizedDescription)
            statusDetail = DriverError.packageNotFound.localizedDescription
            return
        }

        guard NSWorkspace.shared.open(pkgURL) else {
            status = .error(DriverError.installationFailed.localizedDescription)
            statusDetail = DriverError.installationFailed.localizedDescription
            return
        }

        status = .installing
        statusDetail = "Instalador aberto. Conclua a instalação e depois clique em verificar novamente."
    }

    func findDriverDeviceID() -> AudioDeviceID? {
        hardwareInspector
            .allDevices()
            .first(where: { $0.uid.contains(Constants.AudioDriver.DEVICE_UID_SUBSTRING) })?
            .id
    }

    func currentDefaultOutputUID() -> String? {
        hardwareInspector.defaultOutputDevice()?.uid
    }

    func isDriverSelectedAsDefaultOutput() -> Bool {
        guard let outputUID = currentDefaultOutputUID() else { return false }
        return outputUID.contains(Constants.AudioDriver.DEVICE_UID_SUBSTRING)
    }

    func validationPreflightError() -> String? {
        guard let driver = detectedDriver else {
            return "Instale o ArkAudio antes de validar o roteamento."
        }

        guard let output = hardwareInspector.defaultOutputDevice() else {
            return "Não foi possível identificar a saída padrão atual."
        }

        if output.uid == driver.uid {
            return "O ArkAudio está como saída padrão direta. Crie um Multi-Output Device e selecione-o como saída do sistema."
        }

        if let routingIssue = routingIssueMessage(driver: driver, routing: defaultOutputRouting) {
            return routingIssue
        }

        return nil
    }

    func markRoutingValidated(outputUID: String, driverUID: String) {
        validationStore.validatedOutputUID = outputUID
        validationStore.validatedDriverUID = driverUID
        checkInstallation()
    }

    func clearRoutingValidation() {
        validationStore.validatedOutputUID = nil
        validationStore.validatedDriverUID = nil
        checkInstallation()
    }

    func startListeningErrorMessage() -> String {
        switch status {
        case .notInstalled:
            return "Instale o ArkAudio nas Configurações antes de iniciar."
        case .installing:
            return "Conclua a instalação do ArkAudio e verifique novamente."
        case .needsRestart:
            return "Reinicie o Mac para que o ArkAudio apareça como dispositivo de áudio."
        case .legacyDriverInstalled:
            return "Foi detectado apenas o BlackHole legado. Instale o ArkAudio do app."
        case .routingNotVerified:
            return "Finalize o Multi-Output Device e rode a validação do ArkAudio nas Configurações."
        case .installed:
            return "ArkAudio pronto."
        case .error(let message):
            return message
        }
    }

    private func updateStatusForInstalledDriver(_ driver: AudioDeviceSnapshot) {
        guard let currentOutput = defaultOutput else {
            status = .routingNotVerified
            statusDetail = "ArkAudio detectado, mas a saída padrão do sistema não pôde ser lida."
            return
        }

        if currentOutput.uid == driver.uid {
            status = .routingNotVerified
            statusDetail = "ArkAudio detectado, mas ele está como saída padrão direta. Use um Multi-Output Device."
            return
        }

        if let routingIssue = routingIssueMessage(driver: driver, routing: defaultOutputRouting) {
            status = .routingNotVerified
            statusDetail = routingIssue
            return
        }

        if validationStore.validatedDriverUID == driver.uid,
           validationStore.validatedOutputUID == currentOutput.uid {
            status = .installed
            statusDetail = "ArkAudio detectado e roteamento validado para a saída padrão atual."
            return
        }

        status = .routingNotVerified
        if validationStore.validatedOutputUID != nil,
           validationStore.validatedOutputUID != currentOutput.uid {
            statusDetail = "A saída padrão mudou desde a última validação. Rode a validação novamente."
        } else {
            statusDetail = "ArkAudio detectado. Agora crie um Multi-Output Device e valide a captura."
        }
    }

    private func hasLegacyBlackHole(installedDevices: [AudioDeviceSnapshot]) -> Bool {
        if installedDevices.contains(where: { $0.uid.contains(Constants.AudioDriver.LEGACY_DEVICE_UID_SUBSTRING) }) {
            return true
        }

        return hardwareInspector.fileExists(atPath: Constants.AudioDriver.LEGACY_DRIVER_HAL_PATH)
    }

    private func routingIssueMessage(
        driver: AudioDeviceSnapshot,
        routing: AudioOutputRoutingSnapshot?
    ) -> String? {
        guard let routing else { return nil }

        guard routing.kind == .aggregate else {
            return "A saída padrão atual não é um Multi-Output Device. Crie um com sua saída física primeiro e o ArkAudio como secundário."
        }

        guard routing.subdevice(uid: driver.uid) != nil else {
            return "A saída padrão atual não inclui o ArkAudio. Adicione o ArkAudio ao Multi-Output Device."
        }

        if routing.clockDeviceUID == driver.uid {
            return "O ArkAudio está como clock do Multi-Output Device. Use sua saída física como clock principal."
        }

        if routing.mainSubdeviceUID == driver.uid {
            return "O ArkAudio está como dispositivo principal do Multi-Output Device. Use sua saída física como principal."
        }

        if let firstSubdevice = routing.subdevices.first {
            if firstSubdevice.uid == driver.uid {
                return "O ArkAudio está no topo do Multi-Output Device. Deixe sua saída física como primeiro dispositivo e o ArkAudio como secundário."
            }

            if let mainSubdeviceUID = routing.mainSubdeviceUID,
               firstSubdevice.uid != mainSubdeviceUID {
                return "O dispositivo principal do Multi-Output Device não está no topo da lista. Coloque sua saída física primeiro e o ArkAudio como secundário."
            }
        }

        if let driverSubdevice = routing.subdevice(uid: driver.uid),
           driverSubdevice.driftCompensationEnabled == false {
            return "Ative o drift correction no ArkAudio dentro do Multi-Output Device."
        }

        return nil
    }
}

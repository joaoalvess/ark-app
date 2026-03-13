import SwiftUI

struct AudioSetupView: View {
    @Bindable var appState: AppState

    private var driverManager: AudioDriverManager {
        appState.audioManager.driverManager
    }

    private var driverStatus: AudioDriverManager.DriverStatus {
        driverManager.status
    }

    private var validationDisabled: Bool {
        if appState.isListening || appState.isAudioRoutingValidationRunning {
            return true
        }

        switch driverStatus {
        case .installing, .needsRestart, .notInstalled, .legacyDriverInstalled, .error(_):
            return true
        case .routingNotVerified, .installed:
            return false
        }
    }

    var body: some View {
        Section("Áudio") {
            Picker("Dispositivo de entrada", selection: $appState.settingsStore.settings.inputDeviceID) {
                Text("Padrão do sistema").tag(nil as String?)
                ForEach(MicrophoneCaptureService.availableDevices(), id: \.id) { device in
                    Text(device.name).tag(device.id as String?)
                }
            }

            HStack {
                Text("Driver virtual")
                Spacer()
                driverStatusBadge
            }

            Text(driverManager.statusDetail)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Saída padrão atual")
                Spacer()
                Text(driverManager.currentOutputName)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Setup guiado do ArkAudio")
                    .font(.headline)
                Text("1. Instale o ArkAudio usando o botão abaixo.")
                Text("2. Abra o app Configuração de Áudio MIDI e crie um Multi-Output Device com seus alto-falantes e ArkAudio 2ch.")
                Text("3. Deixe sua saída física como dispositivo principal e no topo da lista. O ArkAudio deve ficar como secundário com drift correction.")
                Text("4. Volte aqui, toque qualquer áudio e rode a validação por 5 segundos.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                if driverStatus == .notInstalled || driverStatus == .legacyDriverInstalled {
                    Button("Instalar ArkAudio") {
                        appState.installAudioDriver()
                    }
                }

                Button("Verificar novamente") {
                    appState.recheckDriver()
                }

                Button(appState.isAudioRoutingValidationRunning ? "Validando..." : "Validar ArkAudio") {
                    Task {
                        await appState.validateAudioRouting()
                    }
                }
                .disabled(validationDisabled)
            }

            if let validationMessage = appState.audioRoutingValidationMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: validationIconName)
                        .foregroundStyle(validationColor)
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(validationColor)
                }
            }

            if appState.isAudioRoutingValidationRunning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Toque qualquer áudio no sistema enquanto o ArkAudio é validado.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var driverStatusBadge: some View {
        switch driverStatus {
        case .installed:
            Label("Pronto", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)

        case .routingNotVerified:
            Label("Falta validar", systemImage: "waveform.badge.exclamationmark")
                .foregroundStyle(.orange)

        case .legacyDriverInstalled:
            Label("BlackHole legado", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

        case .notInstalled:
            Label("Não instalado", systemImage: "arrow.down.circle")
                .foregroundStyle(.secondary)

        case .installing:
            Label("Instalando", systemImage: "hourglass")
                .foregroundStyle(.secondary)

        case .needsRestart:
            Label("Reinicie o Mac", systemImage: "arrow.clockwise.circle")
                .foregroundStyle(.orange)

        case .error(_):
            Label("Erro", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var validationIconName: String {
        switch appState.didAudioRoutingValidationSucceed {
        case true:
            return "checkmark.circle.fill"
        case false:
            return "xmark.octagon.fill"
        case nil:
            return "speaker.wave.2"
        }
    }

    private var validationColor: Color {
        switch appState.didAudioRoutingValidationSucceed {
        case true:
            return .green
        case false:
            return .red
        case nil:
            return .secondary
        }
    }
}

import SwiftUI

struct AudioSetupView: View {
    @Bindable var appState: AppState

    private var driverStatus: AudioDriverManager.DriverStatus {
        appState.audioManager.driverManager.status
    }

    var body: some View {
        Section("Audio") {
            Picker("Dispositivo de entrada", selection: $appState.settingsStore.settings.inputDeviceID) {
                Text("Padrao do sistema").tag(nil as String?)
                ForEach(MicrophoneCaptureService.availableDevices(), id: \.id) { device in
                    Text(device.name).tag(device.id as String?)
                }
            }

            HStack {
                Text("Driver de Audio (BlackHole)")
                Spacer()
                driverStatusView
            }
        }
    }

    @ViewBuilder
    private var driverStatusView: some View {
        switch driverStatus {
        case .installed:
            Label("Instalado", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)

        case .notInstalled:
            Button("Instalar Driver") {
                appState.installAudioDriver()
            }

        case .installing:
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Instalando...")
                        .font(.caption)
                }
                Button("Verificar novamente") {
                    appState.recheckDriver()
                }
                .font(.caption)
            }

        case .needsRestart:
            Label("Reinicie o computador", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

        case .error(let message):
            VStack(alignment: .trailing, spacing: 4) {
                Label("Erro", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Verificar novamente") {
                    appState.recheckDriver()
                }
                .font(.caption)
            }
        }
    }
}

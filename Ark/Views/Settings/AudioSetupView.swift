import SwiftUI

struct AudioSetupView: View {
    @Bindable var appState: AppState

    var body: some View {
        Section("Audio") {
            Picker("Dispositivo de entrada", selection: $appState.settingsStore.settings.inputDeviceID) {
                Text("Padrao do sistema").tag(nil as String?)
                ForEach(MicrophoneCaptureService.availableDevices(), id: \.id) { device in
                    Text(device.name).tag(device.id as String?)
                }
            }

            HStack {
                Text("ScreenCaptureKit")
                Spacer()
                if appState.audioManager.systemService.permissionGranted {
                    Label("Permitido", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Verificar Permissao") {
                        Task { await appState.audioManager.systemService.checkPermission() }
                    }
                }
            }
        }
    }
}

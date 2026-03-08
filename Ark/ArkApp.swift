import SwiftUI

@main
struct ArkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar icon
        MenuBarExtra {
            VStack(spacing: 8) {
                HStack {
                    Text("Ark")
                        .font(.headline)
                    Spacer()
                    if appDelegate.appState.isListening {
                        PulsingIndicator(color: .red)
                        Text("Gravando")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal)

                Divider()

                Button(appDelegate.appState.isListening ? "Parar Escuta" : "Iniciar Escuta") {
                    Task { await appDelegate.appState.toggleListening() }
                }
                .keyboardShortcut(.return, modifiers: .command)

                Button("Mostrar/Esconder Painel") {
                    // Toggle panel visibility via the floating panel
                }

                Divider()

                SettingsLink {
                    Text("Configuracoes...")
                }
                .keyboardShortcut(",", modifiers: .command)

                Divider()

                Button("Encerrar Ark") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.vertical, 8)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                if appDelegate.appState.isListening {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                }
            }
        }

        // Settings window
        Settings {
            SettingsView(appState: appDelegate.appState)
        }
    }
}

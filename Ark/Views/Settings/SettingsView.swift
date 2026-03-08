import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState

    var body: some View {
        Form {
            APIConfigView(appState: appState)

            AudioSetupView(appState: appState)

            Section("Modelo WhisperKit") {
                Picker("Modelo", selection: $appState.settingsStore.settings.whisperModel) {
                    Text("large-v3 (melhor qualidade)").tag("large-v3")
                    Text("large-v3-turbo (mais rapido)").tag("large-v3-turbo")
                    Text("medium (leve)").tag("medium")
                }

                HStack {
                    Text("Status do modelo")
                    Spacer()
                    if appState.whisperService.isLoading {
                        ProgressView()
                            .controlSize(.small)
                        Text("Carregando...")
                            .font(.caption)
                    } else if appState.whisperService.isModelLoaded {
                        Label("Carregado", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Nao carregado", systemImage: "circle")
                            .foregroundStyle(.secondary)
                    }
                }

                if !appState.whisperService.isModelLoaded && !appState.whisperService.isLoading {
                    Button("Baixar Modelo") {
                        Task {
                            await appState.whisperService.loadModel(
                                name: appState.settingsStore.settings.whisperModel
                            )
                        }
                    }
                }
            }

            Section("Modelo IA") {
                Picker("Selecionar modelo", selection: $appState.settingsStore.settings.aiModel) {
                    Text("GPT-5.3-Codex").tag("gpt-5.3-codex")
                    Text("GPT-5.4").tag("gpt-5.4")
                    Text("GPT-5.2-Codex").tag("gpt-5.2-codex")
                    Text("GPT-5.1-Codex-Max").tag("gpt-5.1-codex-max")
                    Text("GPT-5.2").tag("gpt-5.2")
                    Text("GPT-5.1-Codex-Mini").tag("gpt-5.1-codex-mini")
                }

                Picker("Selecionar raciocínio", selection: $appState.settingsStore.settings.aiReasoningLevel) {
                    Text("Baixa").tag("low")
                    Text("Média").tag("medium")
                    Text("Alta").tag("high")
                    Text("Altíssimo").tag("max")
                }
            }

            Section("Preferencias") {
                Toggle("Sugestoes automaticas", isOn: $appState.settingsStore.settings.autoSuggest)

                Slider(
                    value: $appState.settingsStore.settings.chunkDuration,
                    in: 5...30,
                    step: 5
                ) {
                    Text("Duracao do chunk: \(Int(appState.settingsStore.settings.chunkDuration))s")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 580)
    }
}

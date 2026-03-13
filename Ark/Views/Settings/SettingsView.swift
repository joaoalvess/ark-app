import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState

    var body: some View {
        Form {
            Section("Perfil do Assistente") {
                Picker("Perfil", selection: $appState.settingsStore.settings.assistantProfile) {
                    ForEach(AssistantProfile.allCases, id: \.self) { profile in
                        VStack(alignment: .leading) {
                            Text(profile.displayName)
                            Text(profile.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(profile)
                    }
                }
            }

            APIConfigView(appState: appState)

            AudioSetupView(appState: appState)

            Section("Transcrição") {
                Picker("Provedor", selection: $appState.settingsStore.settings.transcriptionProvider) {
                    Text("Local").tag(TranscriptionProvider.local)
                    Text("Cloud").tag(TranscriptionProvider.cloud)
                }
                .pickerStyle(.segmented)

                if appState.settingsStore.settings.transcriptionProvider == .local {
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
                } else {
                    Picker("Modelo", selection: $appState.settingsStore.settings.cloudTranscriptionModel) {
                        Text("Mini (rec.)").tag("gpt-4o-mini-transcribe")
                        Text("Standard").tag("gpt-4o-transcribe")
                    }
                    .pickerStyle(.segmented)

                    SecureField("API Key da OpenAI", text: $appState.settingsStore.settings.openAIAPIKey)
                        .onChange(of: appState.settingsStore.settings.openAIAPIKey) {
                            appState.openAIWhisperService.prepare(apiKey: appState.settingsStore.settings.openAIAPIKey)
                        }

                    HStack {
                        Text("Status")
                        Spacer()
                        if appState.openAIWhisperService.isReady {
                            Label("Configurado", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Não configurado", systemImage: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                        }
                    }

                    if let error = appState.openAIWhisperService.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
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
                    in: Constants.Suggestion.TRANSCRIPTION_WINDOW_MIN_SECONDS...Constants.Suggestion.TRANSCRIPTION_WINDOW_MAX_SECONDS,
                    step: 1
                ) {
                    Text("Janela de transcricao: \(Int(appState.settingsStore.settings.chunkDuration))s")
                }

                Text("A janela de transcricao define quanto contexto o Whisper recebe por vez. Mudanças passam a valer na próxima escuta.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 700)
        .onAppear {
            migrateKeychainKeyIfNeeded()
            appState.recheckDriver()
            appState.openAIWhisperService.prepare(apiKey: appState.settingsStore.settings.openAIAPIKey)
        }
    }

    private func migrateKeychainKeyIfNeeded() {
        let keychainKey = "openai_api_key"
        if appState.settingsStore.settings.openAIAPIKey.isEmpty,
           let savedKey = KeychainService.load(key: keychainKey),
           !savedKey.isEmpty {
            appState.settingsStore.settings.openAIAPIKey = savedKey
            KeychainService.delete(key: keychainKey)
        }
    }
}

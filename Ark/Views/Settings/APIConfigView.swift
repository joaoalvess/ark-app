import SwiftUI

struct APIConfigView: View {
    @Bindable var appState: AppState
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var testResult: Bool?

    private var activeStep: Int {
        if !appState.codexService.isAvailable { return 1 }
        if !appState.codexService.isAuthenticated { return 2 }
        return 3
    }

    var body: some View {
        Section("Codex CLI") {
            stepRow(
                step: 1,
                icon: "terminal",
                title: "Instalar Codex CLI",
                subtitle: activeStep == 1 ? "Necessario Node.js instalado" : nil,
                isComplete: activeStep > 1
            ) {
                Button("Instalar Codex CLI") {
                    runAction {
                        let result = await appState.codexService.installCodex()
                        if !result.success { throw SetupError(message: result.message) }
                    }
                }
                .disabled(isLoading)
            }

            stepRow(
                step: 2,
                icon: "person.badge.key",
                title: "Autenticar no OpenAI",
                subtitle: activeStep == 2 ? "O navegador sera aberto para autenticacao OAuth" : nil,
                isComplete: activeStep > 2
            ) {
                Button("Fazer Login") {
                    runAction {
                        let result = await appState.codexService.login()
                        if !result.success { throw SetupError(message: result.message) }
                    }
                }
                .disabled(isLoading || activeStep < 2)
            }

            stepRow(
                step: 3,
                icon: "checkmark.seal.fill",
                title: "Tudo configurado!",
                subtitle: nil,
                isComplete: testResult == true
            ) {
                Button("Testar Conexao") {
                    runAction {
                        let success = await appState.codexService.testConnection()
                        testResult = success
                        if !success { throw SetupError(message: "Falha na conexao") }
                    }
                }
                .disabled(isLoading || activeStep < 3)
            }

            if isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Aguarde...")
                        .foregroundStyle(.secondary)
                }
            }

            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            if testResult == true {
                Label("Conexao OK", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .onAppear {
            Task { await appState.codexService.checkAvailability() }
        }
    }

    private func stepRow(
        step: Int,
        icon: String,
        title: String,
        subtitle: String?,
        isComplete: Bool,
        @ViewBuilder action: () -> some View
    ) -> some View {
        HStack {
            Image(systemName: isComplete ? "checkmark.circle.fill" : icon)
                .foregroundStyle(isComplete ? .green : activeStep == step ? .accentColor : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(activeStep == step ? .primary : .secondary)
                if let subtitle, activeStep == step {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if activeStep == step && !isComplete {
                action()
            }
        }
    }

    private func runAction(_ block: @escaping () async throws -> Void) {
        isLoading = true
        errorMessage = nil
        testResult = nil
        Task {
            do {
                try await block()
            } catch let error as SetupError {
                errorMessage = error.message
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

private struct SetupError: Error {
    let message: String
}

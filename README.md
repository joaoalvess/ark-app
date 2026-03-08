# 🛡️ Ark

**Seu copiloto invisível para entrevistas de emprego.**

Ark é um app nativo para macOS que roda discretamente na menu bar, capturando áudio em tempo real (microfone + áudio do sistema), transcrevendo com Whisper e usando IA para sugerir respostas durante entrevistas.

---

## ✨ Features

- 🎙️ **Captura de áudio dual** — grava simultaneamente o microfone (você) e o áudio do sistema (entrevistador)
- 📝 **Transcrição em tempo real** — powered by Whisper (`large-v3`), com suporte nativo a português
- 🤖 **Sugestões automáticas** — a IA analisa o que o entrevistador disse e sugere respostas na hora
- 💬 **Chat integrado** — painel flutuante para fazer perguntas sobre a entrevista em andamento
- 🔥 **Streaming de respostas** — respostas da IA aparecem em tempo real, sem esperar
- ⚡ **Floating bar** — interface minimalista em formato pill que flutua sobre qualquer app
- 🎯 **Menu bar** — controle rápido via ícone na barra de menus com atalho global (`⌘ + Enter`)
- ⚙️ **Configurável** — modelo de IA, modelo Whisper, dispositivo de áudio, nível de raciocínio

## 🏗️ Arquitetura

```
Ark/
├── App/                    # AppDelegate, AppState, Constants
├── Models/                 # ChatMessage, Settings, TranscriptEntry
├── Services/
│   ├── Audio/              # Captura de mic e áudio do sistema
│   ├── Transcription/      # Whisper + gerenciamento de transcrição
│   ├── AI/                 # Integração com Codex CLI
│   └── Persistence/        # UserDefaults store
├── Views/
│   ├── FloatingBar/        # Barra flutuante principal
│   ├── ChatPanel/          # Painel de chat com IA
│   ├── Components/         # GlassPanel, PulsingIndicator
│   └── Settings/           # Telas de configuração
├── Window/                 # FloatingPanelController
└── Resources/              # Assets
```

## 🔧 Requisitos

- macOS 14.0+
- Xcode 15+
- [Codex CLI](https://github.com/openai/codex) instalado (`npm install -g @openai/codex`)
- Permissões de microfone e gravação de tela

## 🚀 Como usar

1. Clone o repositório
2. Abra `Ark.xcodeproj` no Xcode
3. Build and run (`⌘ + R`)
4. O ícone 🎙️ aparece na menu bar
5. Configure a API key nas configurações (`⌘ + ,`)
6. Inicie a escuta com `⌘ + Enter` e abra o chat

## 🛠️ Stack

| Camada | Tecnologia |
|--------|-----------|
| UI | SwiftUI + AppKit |
| Áudio | AVFoundation + ScreenCaptureKit |
| Transcrição | Whisper (local) |
| IA | OpenAI Codex CLI |
| Persistência | UserDefaults |

## 📄 Licença

Este projeto é de uso pessoal.

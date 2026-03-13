# 🛡️ Ark

**Personal AI assistant for macOS** — real-time transcription + contextual AI in a floating panel.

Ark is a native macOS app that lives in your menu bar, capturing conversation audio in real time (microphone + system audio), transcribing with Whisper, and providing contextual AI suggestions through a sleek floating panel. Perfect for meetings, calls, pair programming, coaching sessions, and study groups.

---

## ✨ Features

- 🎙️ **Dual audio capture** — records your microphone and system audio (calls, meetings) simultaneously
- 📝 **Real-time transcription** — powered by Whisper (`large-v3`) with native Portuguese support
- 🤖 **Contextual suggestions** — AI analyzes the conversation and provides relevant suggestions on the spot
- 💬 **Built-in chat** — floating panel to ask questions about the ongoing conversation
- 🎭 **Multiple profiles** — generalist, code review, tech coaching — tailor the assistant to your context
- 🔥 **Streaming responses** — AI answers appear in real time, no waiting
- ⚡ **Floating bar** — minimal pill-shaped interface that floats over any app
- 🎯 **Menu bar** — quick controls via menu bar icon with global shortcut (`Cmd + Enter`)
- ⚙️ **Configurable** — AI model, Whisper model, audio device, reasoning level

## 🏗️ Architecture

```
Ark/
├── App/                    # AppDelegate, AppState, Constants
├── Models/                 # ChatMessage, Settings, TranscriptEntry, AssistantProfile
├── Services/
│   ├── Audio/              # Mic & system audio capture
│   ├── Transcription/      # Whisper + transcript management
│   ├── AI/                 # Codex CLI integration
│   └── Persistence/        # UserDefaults store
├── Views/
│   ├── FloatingBar/        # Main floating bar
│   ├── ChatPanel/          # AI chat panel
│   ├── Components/         # GlassPanel, PulsingIndicator
│   └── Settings/           # Settings screens
├── Window/                 # FloatingPanelController
└── Resources/              # Assets
```

## 🔧 Requirements

- macOS 14.0+
- Xcode 15+
- [Codex CLI](https://github.com/openai/codex) installed (`npm install -g @openai/codex`)
- Microphone and screen recording permissions

## 🚀 Getting Started

1. Clone the repository
2. Open `Ark.xcodeproj` in Xcode
3. Build and run (`Cmd + R`)
4. The mic icon appears in the menu bar
5. Set up your API key in settings (`Cmd + ,`)
6. Start listening with `Cmd + Enter` and open the chat

## 🛠️ Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI + AppKit |
| Audio | AVFoundation + ScreenCaptureKit |
| Transcription | Whisper (on-device) |
| AI | OpenAI Codex CLI |
| Persistence | UserDefaults |

## 📄 License

This project is licensed under the [MIT License](LICENSE).

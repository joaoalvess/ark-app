# Ark

macOS interview copilot — real-time transcription + AI-powered suggestions via a floating panel.

## Build & Run

- Open `Ark.xcodeproj` in Xcode 15+
- Target: macOS 14.0+
- Dependencies managed via Swift Package Manager (WhisperKit)
- External dependency: [Codex CLI](https://github.com/openai/codex) installed via npm

## Architecture

Service-based architecture with Observable state, MVVM-influenced.

```
AppState (central hub, @MainActor @Observable)
├── AudioSessionManager (orchestrates mic + system audio)
│   ├── MicrophoneCaptureService (AVAudioEngine)
│   ├── SystemAudioCaptureService (AVAudioEngine via BlackHole)
│   ├── AudioDriverManager (BlackHole detection/installation)
│   └── AggregateDeviceManager (multi-output device lifecycle)
├── WhisperService (on-device STT via WhisperKit)
├── TranscriptManager (rolling 30-min transcript)
├── InterviewAssistantEngine (turn-based suggestion state machine)
├── CodexCLIService (AI chat via Codex CLI subprocess)
└── SettingsStore (UserDefaults persistence)
```

**Data flow**: Audio chunks (15s @ 16kHz) → WhisperService → TranscriptManager → auto-suggestion → CodexCLIService → streaming response → UI update.

**UI layer**: NSPanel (AppKit) hosts SwiftUI views via NSHostingView. FloatingPanelController manages sizing/positioning.

## Code Conventions

- **Code** (variables, functions, comments): English
- **UI strings and user-facing text**: Portuguese
- Services: `[Functionality]Service` or `[Functionality]Manager`
- Views: `[Feature]View` or `[Feature]Button`
- Constants: `SCREAMING_SNAKE_CASE` inside the `Constants` enum
- Guard statements for early returns
- Weak self captures in escaping closures

## Key Swift Patterns

- `@Observable` / `@MainActor` for state (Observation framework, not Combine)
- `@Bindable` in views for two-way bindings
- `async/await` + `Task` for concurrency
- `@unchecked Sendable` for thread-safe FFI wrappers (WhisperService, SystemAudioCaptureService, AggregateDeviceManager)
- `NSLock` for thread-safe audio buffers

## Project Structure

```
Ark/
├── App/           AppState, AppDelegate, Constants
├── Models/        ChatMessage, Settings, TranscriptEntry, AssistantProfile
├── Services/
│   ├── Audio/     AudioSessionManager, Mic/System capture, AudioDriverManager, AggregateDeviceManager
│   ├── Transcription/  WhisperService, TranscriptManager
│   ├── AI/        CodexCLIService, PromptBuilder, InterviewAssistantEngine
│   └── Persistence/    SettingsStore
├── Views/
│   ├── FloatingBar/    FloatingBarView, MicButton, AskButton
│   ├── ChatPanel/      ChatPanelView, messages, input, suggestions
│   ├── Settings/       SettingsView, APIConfigView, AudioSetupView
│   └── Components/     GlassPanel, PulsingIndicator
├── Window/        FloatingPanelController (NSPanel)
└── Resources/     Assets.xcassets, ArkAudioDriver.pkg
```

## Important Files

| File | Role |
|------|------|
| `Ark/App/AppState.swift` | Central observable state, wires all services together |
| `Ark/App/Constants.swift` | UI dimensions, audio config (sample rate, chunk duration), timeouts |
| `Ark/Services/AI/CodexCLIService.swift` | Codex CLI subprocess wrapper with streaming |
| `Ark/Services/Audio/AudioSessionManager.swift` | Dual audio capture orchestration |
| `Ark/Window/FloatingPanelController.swift` | NSPanel sizing and positioning |

## Dependencies

- **WhisperKit** (SPM) — on-device speech-to-text, model: `large-v3`, language: `pt`
- **Codex CLI** (npm, external subprocess) — AI chat completions
- **BlackHole 2ch** (virtual audio driver) — system audio capture without Screen Recording permission
- macOS frameworks: AVFoundation, CoreAudio, AppKit, SwiftUI

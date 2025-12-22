# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OnesecCore is a macOS menu bar application (LSUIElement) for voice-to-text dictation. It captures audio via hotkeys, streams to a WebSocket server for speech recognition, and pastes results into the active application. Built with Swift Package Manager as a headless executable bundled into an app.

## Build Commands

```bash
# Build for current architecture (debug)
swift build

# Build release for both architectures (ARM64 + x86_64) and create signed app bundle
./build_and_sign.sh

# Run tests
swift test
```

## Architecture

### Core Flow
1. **InputController** monitors global hotkeys via CGEventTap
2. **AudioUnitRecorder** captures microphone input, encodes to Opus via **OggOpusPacketizer**
3. **WebSocketAudioStreamer** streams audio and receives transcription results via Starscream
4. **AXPasteboardController** pastes results into focused app using Accessibility APIs

### Key Components

**Sources/Config/** - Configuration and message types
- `Config.swift` - Singleton managing user settings, hotkeys, text processing modes
- `Message.swift` - WebSocket message types and notification enums

**Sources/Input/** - User input handling
- `InputController.swift` - Global hotkey detection via CGEventTap
- `Audio/AudioUnitRecorder.swift` - Audio capture and Opus encoding
- `Key/KeyStateTracker.swift` - Hotkey combination state machine

**Sources/Network/** - Network communication
- `Server/WebSocketAudioStreamer.swift` - WebSocket client for audio streaming to recognition server
- `Client/UDSClient.swift` - Unix Domain Socket for IPC with parent app

**Sources/Service/** - Core services
- `ConnectionCenter.swift` - Central hub managing WSS/UDS connections, permissions, network state
- `EventBus.swift` - Pub/sub event system using Combine
- `AX/*.swift` - Accessibility API wrappers for text manipulation

**Sources/UI/** - SwiftUI status panel and notifications
- `Panel/` - Floating panels for status display
- `Components/` - Reusable UI components

### Event-Driven Architecture
The app uses `EventBus` (Combine-based) for decoupled communication:
- `AppEvent` enum defines all events (recording state, server responses, hotkeys)
- Components subscribe to relevant events via `EventBus.shared.events`

### Recording Modes
- `normal` - Standard dictation
- `command` - Command mode with different processing
- `free` - Free talk mode

## Development Notes

- Mock server in `Mock/` for testing UDS communication (run with `pnpm dev`)
- Requires Accessibility and Microphone permissions at runtime
- App runs as background-only (`LSBackgroundOnly: true`) with menu bar presence
- Uses SwiftyBeaver for logging (`log.debug/info/warning/error`)

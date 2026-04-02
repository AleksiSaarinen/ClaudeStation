# ClaudeStation

A lightweight native macOS app for managing multiple Claude Code sessions with a message queue system.

## Features

- **Multi-session tabs** — Run 2+ Claude Code instances side by side with a sidebar for quick switching (Cmd+1/2/3...)
- **Message queue** — Type messages while Claude is busy. They queue up and auto-send when Claude is ready. Option to send immediately if needed.
- **Bypass permissions always on** — `--dangerously-skip-permissions` enabled by default (configurable)
- **Launch profiles** — Save preset configurations (directory + flags) for your projects
- **Status detection** — Visual indicators showing if each session is idle, running, or waiting for input
- **Queue management** — Reorder, delete, or force-send queued messages. Clear all with one click.

## Architecture

```
ClaudeStation/
├── ClaudeStationApp.swift       # App entry point, window + commands
├── Models/
│   ├── Session.swift            # Session data model + QueuedMessage
│   └── AppSettings.swift        # Persisted preferences + LaunchProfile
├── Services/
│   ├── SessionManager.swift     # Session lifecycle, queue processing
│   └── TerminalService.swift    # PTY process spawning, I/O, status detection
└── Views/
    ├── ContentView.swift        # Root layout: sidebar + detail
    ├── SessionDetailView.swift  # Terminal output + input bar + toolbar
    ├── MessageQueuePanel.swift  # Queue panel with reorder/delete/send
    └── SettingsAndProfiles.swift # Preferences + launch profile management
```

## How the Queue Works

1. **Enter sends to queue** — Your default action queues the message
2. **Shift+Enter sends immediately** — Bypass the queue when you need to
3. **Auto-processing** — When Claude finishes and shows its prompt (`❯`), the next queued message sends automatically
4. **Manual control** — "Send Next" button to manually trigger, or "Send Now" on any individual message
5. **Reorderable** — Drag messages in the queue to change priority

## Building

### Option A: Xcode
Open `ClaudeStation.xcodeproj` in Xcode and build/run (Cmd+R).

### Option B: Swift Package Manager
```bash
cd ClaudeStation
swift build
swift run
```

> Requires macOS 14+ and Swift 5.9+

## Configuration

Go to **Settings** (Cmd+,) to configure:
- Path to `claude` binary (default: `/usr/local/bin/claude`)
- Default working directory
- Toggle bypass permissions
- Queue auto-processing behavior
- Output buffer size

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+T | New session |
| Cmd+1-9 | Switch to session |
| Enter | Queue message |
| Shift+Enter | Send immediately |
| Cmd+, | Settings |

## TODO / Future Ideas

- [ ] True PTY integration with `forkpty()` for full terminal emulation (ANSI colors, cursor movement)
- [ ] SwiftTerm or similar library for proper terminal rendering
- [ ] Drag-and-drop file paths into the input bar
- [ ] Session output search (Cmd+F within terminal)
- [ ] Token/cost tracking per session
- [ ] Export session logs
- [ ] Touch Bar / Menu Bar quick actions
- [ ] Notification Center alerts when a session needs attention

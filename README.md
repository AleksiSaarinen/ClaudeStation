# ClaudeStation

A native macOS app for managing Claude Code sessions with a chat UI, message queue, and pixel pet companion.

**[Download latest release](https://github.com/AleksiSaarinen/ClaudeStation/releases/latest)** — unzip, drag to Applications, right-click → Open.

## Features

- **Chat UI** — Structured responses with tool use cards, markdown rendering, syntax highlighting, and collapsible reasoning
- **Stream-JSON API** — Uses `claude -p --output-format stream-json` for clean structured responses with word-by-word streaming
- **Message Queue** — Type messages while Claude is working; they auto-send when ready
- **Multi-Session Tabs** — Chrome-style tab bar, Cmd+T for new sessions, double-click to rename
- **Command Palette** — Cmd+K to search actions, switch sessions, change directory
- **13 Themes** — Midnight, Aurora, Rosé, Paper, Phosphor, Deep Sea, Amber, Sakura, Violet, Neon, Melon, Sorbet, Frutiger Aero
- **Cursor Packs** — 10 custom cursor packs: System, Mickey Glove, Wii, Blue Glass, Bibata (Classic/Ice/Amber), Kenney Pixel, Win11 (Light/Dark)
- **Font Picker** — Choose from 10 monospace fonts (Menlo, JetBrains Mono, Fira Code, etc.)
- **Smart Suggestions** — AI-powered follow-up action chips after Claude finishes, with ghost text and Tab to autofill
- **Pixel Pet** — Animated companion that reacts to Claude's activity (coding, reading, thinking, success, error)
- **Bubble Particles** — Animated bubble-shaped particles on bright themes, glow particles on dark themes
- **Drag & Drop Images** — Drop screenshots or files onto the window, click thumbnails to preview
- **Session Persistence** — Chat history and sessions survive app restarts
- **Notifications** — macOS notification when Claude finishes and app is in background
- **Plan Mode** — Toggle to use `--permission-mode plan`
- **Liquid Glass UI** — Glass effects on input bar, thinking indicator, suggestion chips (macOS 26+)
- **Custom App Icon** — Purple terminal prompt icon

## Requirements

- macOS 14+ (Sonoma)
- [Claude Code CLI](https://claude.ai/code) installed
- Swift 5.9+

## Build & Run

```bash
git clone https://github.com/AleksiSaarinen/ClaudeStation.git
cd ClaudeStation
bash build.sh
open build/ClaudeStation.app
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Enter | Send message (or queue if busy) |
| Tab | Autofill suggested action into input |
| Cmd+T | New session |
| Cmd+K | Command palette |
| Cmd+1-9 | Switch to session by index |
| Cmd+, | Settings |

## Architecture

```
Sources/
├── ClaudeStationApp.swift    # App entry, window, URL scheme, dock menu
├── ContentView.swift         # Chrome-style tab bar + session switching
├── SessionDetailView.swift   # Chat area, input bar, attachments
├── ChatView.swift            # Message rendering, markdown, syntax highlighting
├── ChatMessage.swift         # Message/block models (Codable for persistence)
├── Session.swift             # Session model
├── SessionManager.swift      # Session lifecycle, queue, persistence
├── TerminalService.swift     # claude CLI communication via stream-json
├── Theme.swift               # 13 themes + animated gradient/particle backgrounds
├── GlassCursors.swift        # Custom cursor packs with method swizzling
├── PetView.swift             # Animated pixel pet (clawd sprite frames)
├── CommandPalette.swift      # Cmd+K action search
├── PasteboardWatcher.swift   # Screenshot/clipboard detection
├── SessionPersistence.swift  # JSON save/restore
├── SettingsView.swift        # Theme picker, font picker, profiles
└── MessageQueuePanel.swift   # Inline queue strip
```

## How It Works

Instead of parsing raw terminal output, ClaudeStation uses Claude Code's structured API:

```bash
claude -p --output-format stream-json --verbose --include-partial-messages --resume <session_id> 'message'
```

Each response comes as clean JSON events:
- `system` — session ID for multi-turn conversations
- `stream_event` — word-by-word text streaming
- `assistant` — structured content blocks (text, tool_use)
- `tool_result` — tool output
- `result` — duration, cost

## Cursor Pack Credits

| Pack | Source | License |
|------|--------|---------|
| Bibata (Classic/Ice/Amber) | [ful1e5/Bibata_Cursor](https://github.com/ful1e5/Bibata_Cursor) | MIT |
| Kenney Pixel | [Kenney Cursor Pack](https://kenney.nl/assets/cursor-pack) | CC0 1.0 |
| Mickey Glove | [SweezyCursors](https://sweezy-cursors.com/) | Free |
| Wii | [rw-designer.com/cursor-set/wii-cursor-by-stefano-tinaglia](https://www.rw-designer.com/cursor-set/wii-cursor-by-stefano-tinaglia) | Free |
| Blue Glass | [rw-designer.com/cursor-set/clear-blueglass](https://www.rw-designer.com/cursor-set/clear-blueglass) | Free |
| Aero No Tail | [rw-designer.com/cursor-set/aero-no-tail](https://www.rw-designer.com/cursor-set/aero-no-tail) | Free |
| Stained Glass | [rw-designer.com/cursor-set/stained-glass](https://www.rw-designer.com/cursor-set/stained-glass) | CC BY |
| Win11 Light/Dark | [jepricreations on DeviantArt](https://www.deviantart.com/jepricreations/art/Windows-11-Cursors-Concept-1125712444) | Free |

## License

MIT

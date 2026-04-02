# ClaudeStation — CLAUDE.md

## What This Is

ClaudeStation is a **native macOS SwiftUI app** that manages multiple Claude Code terminal sessions with a **message queue system**. Think of it as a purpose-built terminal multiplexer specifically for Claude Code workflows.

The user (Allu) currently runs 2-3 Claude Code instances in separate Terminal.app windows, manually toggling bypass permissions each time, and sometimes corrupts Claude's state by sending input while it's mid-task. This app solves all of that.

## Tech Stack

- **Language:** Swift 5.9+
- **UI:** SwiftUI (macOS 14+ / Sonoma)
- **Process management:** Foundation `Process` + `Pipe` for spawning Claude Code
- **No external dependencies** — pure Apple frameworks
- **Build:** Swift Package Manager (`Package.swift`) or Xcode

## Architecture Overview

```
ClaudeStation/
├── Package.swift                    # SPM build config, macOS 14+
├── CLAUDE.md                        # This file
├── README.md                        # User-facing docs
└── ClaudeStation/
    ├── ClaudeStationApp.swift       # @main entry, WindowGroup + Commands
    ├── Models/
    │   ├── Session.swift            # Session model, QueuedMessage, SessionStatus enum
    │   └── AppSettings.swift        # @AppStorage preferences, LaunchProfile
    ├── Services/
    │   ├── SessionManager.swift     # Session lifecycle, queue processing logic
    │   └── TerminalService.swift    # Process spawning, I/O pipes, status detection
    └── Views/
        ├── ContentView.swift        # NavigationSplitView: sidebar + detail
        ├── SessionDetailView.swift  # Terminal output + input bar + header
        ├── MessageQueuePanel.swift  # Queue list with reorder/delete/send-now
        └── SettingsAndProfiles.swift # Settings window + launch profiles sheet
```

## Core Feature: Message Queue

This is THE key feature. The problem: if you type into Claude Code while it's running a task, the input can corrupt its state or get lost. The queue solves this.

### How It Should Work

1. **User types a message and presses Enter** → message goes to the queue (NOT sent to Claude Code)
2. **User presses Shift+Enter** → message sends immediately to Claude Code (bypass queue)
3. **Queue auto-processes** → when Claude Code finishes its current task and shows its input prompt, the next message in the queue automatically sends
4. **Queue is visible** in a right-side panel showing all pending messages
5. **Queue is manageable** → reorder (drag), delete, force-send individual messages
6. **Queue badge** shows on the session in the sidebar (e.g., "2" orange badge)

### Queue State Machine

```
User types + Enter
    → QueuedMessage added to session.messageQueue (status: .pending)
    → If session.status == .waitingForInput AND autoProcessQueue is on:
        → Immediately dequeue and send
    → Else:
        → Message stays in queue

Claude Code finishes task (detected by output heuristics)
    → session.status changes to .waitingForInput
    → If messageQueue is not empty:
        → Small delay (300ms) to avoid race conditions
        → Dequeue first message, send to process stdin
        → session.status changes to .running

User clicks "Send Now" on a queued message
    → Remove from queue, send to stdin immediately regardless of status

User clicks "Send Now" button in input bar (Shift+Enter)
    → Send directly to stdin, never touches queue
```

## Status Detection (Critical — Needs Real Testing)

The `TerminalService.detectStatus()` method uses heuristic pattern matching on Claude Code's stdout to determine its state. **This is the most important thing to get right** because the queue auto-processing depends on it.

### What to detect

| State | Meaning | Heuristics (need refinement) |
|-------|---------|------------------------------|
| `.running` | Claude is actively working | Spinner characters (⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏), "Running", "Churned", active output streaming |
| `.waitingForInput` | Claude's prompt is showing, ready for input | The `❯` prompt character, `>` at start of line after a blank line, no output for N seconds |
| `.idle` | Session started but Claude Code not launched yet, or process terminated | Process not running or terminated |
| `.error` | Something went wrong | Process exit code != 0, error strings in output |

### Important considerations for status detection

- Claude Code outputs ANSI escape codes for colors/formatting — these need to be stripped or handled when pattern matching
- The prompt character might be preceded by ANSI codes: `\e[1;32m❯\e[0m` or similar
- There may be a delay between Claude finishing output and showing the prompt
- Plan mode shows a different prompt/flow — the user might approve/reject
- The `/btw` side-question feature has its own prompt
- When Claude asks "Do you want to proceed?" type questions, that's also `.waitingForInput`

### Recommended approach

1. Strip ANSI escape codes from output before pattern matching
2. Use a combination of prompt detection AND silence detection (no output for 1-2 seconds after a burst)
3. Track the last N lines of output for context, not just the latest chunk
4. Add a configurable debug mode that logs all status transitions

## Session Lifecycle

```
createSession(name, workingDirectory)
    → Session object created, added to sessions array
    → Appears in sidebar as "Idle"

launchSession(session)
    → TerminalService.launch() spawns /bin/zsh -l -c "cd <dir> && claude [flags]"
    → Status → .running
    → Output starts streaming to session.outputBuffer

User interacts via input bar / queue
    → Messages sent to process.stdin via inputPipe

closeSession(id)
    → Process terminated (SIGTERM)
    → Session removed from array
    → If it was active, switch to another session
    → Always keep at least 1 session
```

## Bypass Permissions

The `--dangerously-skip-permissions` flag is passed to Claude Code by default. This is controlled by `AppSettings.alwaysBypassPermissions` (defaults to `true`). When building the claude command in `TerminalService.launch()`, check this setting.

The Claude Code binary path is configurable (default: `/usr/local/bin/claude`) because it might be installed elsewhere.

## UI Layout

```
┌─────────────────────────────────────────────────────┐
│ [traffic lights]              ClaudeStation         │
├──────────┬──────────────────────────┬───────────────┤
│ Sessions │ ~/Documents/GitHub/alt.. │  ● Running    │
│          ├──────────────────────────┤               │
│ ● altegro│                          │ Message queue │
│   Running│  Terminal output area    │               │
│          │  (scrollable, mono)      │  #1 add conf..│
│ ● aether.│                          │     [send][x] │
│   Waiting│  Claude Code v2.1.89     │               │
│     [2]  │  Opus 4.6 ...           │  #2 run tests │
│          │  ● Running... (47s)      │     [send][x] │
│ ○ ward-47│  ● Pushed.              │               │
│   Idle   │  ❯ █                    │               │
│          ├──────────────────────────┤  [send next]  │
│ [+ New]  │ ❯ [input...............]│  [clear all]  │
│          │         [Queue] [Send]   │               │
└──────────┴──────────────────────────┴───────────────┘
```

- **Left sidebar** (220px): Session list with status dots and queue badges
- **Center**: Terminal output (scrollable, monospaced) + input bar at bottom
- **Right panel** (260px, toggleable): Message queue with controls
- **Header bar**: Working directory path + status pill

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+T | New session |
| Cmd+1 through Cmd+9 | Switch to session by index |
| Enter | Add message to queue |
| Shift+Enter | Send message immediately |
| Cmd+, | Open settings |
| Cmd+W | Close current session (with confirmation if running) |

## Settings (Cmd+,)

**General tab:**
- Claude Code binary path (text field, default `/usr/local/bin/claude`)
- Default working directory (text field, default `~`)
- Always bypass permissions (toggle, default ON)
- Max output buffer lines (stepper, default 10000)

**Queue tab:**
- Auto-process queue when Claude is ready (toggle, default ON)
- Show notifications for queue events (toggle, default ON)

## Launch Profiles

Saved configurations for quick session startup. Stored in UserDefaults as JSON.

Each profile has:
- Name (e.g., "Altegro", "Aetheria")
- Working directory
- Extra flags (string array)
- Plan mode toggle

Profiles are managed via a sheet (accessible from toolbar). Each profile has a "Launch" button that creates + starts a session with those settings.

## Minigame: Kick the Claude

ClaudeStation includes an embedded "Kick the Claude" minigame — an Interactive Buddy / Kick the Boss style beat-em-up that runs while you wait for Claude to finish tasks. It lives in a WKWebView panel.

### Architecture

The minigame is a self-contained React app (`kick-the-claude.jsx`) that gets built into a single HTML file and bundled in the app's Resources. The Swift app communicates with it via WKWebView's `evaluateJavaScript` and `WKScriptMessageHandler`.

### File Structure

```
ClaudeStation/
├── ClaudeStation/
│   ├── Minigame/
│   │   ├── MinigameView.swift          # SwiftUI view wrapping WKWebView
│   │   ├── MinigameBridge.swift        # Swift ↔ JS communication layer
│   │   └── Resources/
│   │       └── kick-the-claude.html    # Built/bundled HTML (from React source)
│   └── ...
├── kick-the-claude.jsx                 # React source (for development/iteration)
└── ...
```

### Integration Points with ClaudeStation

The minigame is NOT just a standalone game — it ties into the actual Claude Code session activity:

#### Swift → JS (events from ClaudeStation to the game)

Call these via `webView.evaluateJavaScript()`:

```javascript
// When Claude finishes a task (KO detected → session goes from .running to .waitingForInput)
window.claudeEvent('taskComplete', { tokens: 50, taskType: 'code' })

// When Claude starts a task (session goes from .waitingForInput to .running)
window.claudeEvent('taskStarted', { estimatedDuration: 30 })

// When a session milestone happens (e.g., successful git push detected in output)
window.claudeEvent('milestone', { type: 'gitPush', bonus: 100 })

// Session status change
window.claudeEvent('sessionStatus', { status: 'running' | 'waiting' | 'idle' })
```

#### JS → Swift (game events back to the app)

The game posts messages via `window.webkit.messageHandlers.claudeStation.postMessage()`:

```javascript
// Game wants to show a notification (e.g., rank up)
{ type: 'notification', title: 'Rank Up!', body: 'You are now a Senior Dev' }

// Game state for persistence (auto-save)
{ type: 'saveState', state: { tokens: 1234, level: 5, weapons: [...], ... } }

// Player unlocked something noteworthy
{ type: 'achievement', name: 'CTO of Violence' }
```

#### Token Economy Integration

The game earns tokens from two sources:
1. **Clicking the buddy** (the base game mechanic)
2. **Claude completing tasks** (passive rewards while Claude works)

This means: the more you use Claude Code, the more tokens you earn, the more weapons/upgrades you unlock. This creates a fun loop where heavy Claude usage = faster game progression.

Suggested bonus token rates:
- Task complete: 20-100 tokens (based on duration — longer tasks = more tokens)
- Git push detected: +50 bonus
- Test suite pass detected: +30 bonus
- Build success detected: +20 bonus
- Error/failure: +5 pity tokens

#### Where It Lives in the UI

The minigame panel is accessible from:
1. **A tab in the session detail view** — swap between Terminal and Minigame views
2. **Or a separate window** — Cmd+G to pop out the minigame into its own window (so you can play while watching terminal output)

The recommended approach is a tab alongside the terminal output, replacing the terminal view when active. The queue panel stays visible so you can still manage messages.

```
┌──────────┬──────────────────────────┬───────────────┐
│ Sessions │ [Terminal] [Minigame]    │ Message queue  │
│          ├──────────────────────────┤               │
│ ● altegro│                          │  #1 add conf..│
│   Running│  ┌──────────────────┐   │     [send][x] │
│          │  │  KICK THE CLAUDE │   │               │
│ ● aether.│  │                  │   │  #2 run tests │
│   Waiting│  │    (buddy)       │   │     [send][x] │
│     [2]  │  │                  │   │               │
│          │  │  ◆ 1,234 tokens  │   │               │
│ ○ ward-47│  └──────────────────┘   │  [send next]  │
│   Idle   │                          │  [clear all]  │
│          ├──────────────────────────┤               │
│ [+ New]  │ ❯ [input bar still here]│               │
└──────────┴──────────────────────────┴───────────────┘
```

### Building the HTML Bundle

The React JSX needs to be compiled into a single HTML file for WKWebView. Options:
1. **Simple:** Use an online tool or esbuild to bundle the JSX into vanilla JS, then wrap in an HTML file with the styles inlined
2. **Better:** Set up a small Vite/esbuild config that outputs a single `kick-the-claude.html` with everything inlined
3. **For development:** Use Vite dev server and point WKWebView at localhost during development

For the MVP, option 1 is fine — just get a working HTML file into Resources/.

### Game State Persistence

Save/load game state through the bridge:
- **Swift side:** Store game state JSON in UserDefaults (key: `minigameState`)
- **On load:** Swift sends saved state to JS via `window.loadState(json)`
- **On save:** JS posts state to Swift via messageHandler (auto-save every 30 seconds + on app quit)
- Game state includes: tokens, level, knockouts, totalDamage, unlocked weapons, bought upgrades, rank

### Future Ideas for the Minigame

- **Claude-themed weapons:** "Prompt injection" (poison damage over time), "Hallucination beam" (random damage), "System prompt" (stun/freeze)
- **Cosmetic unlocks:** Hats and outfits for the buddy (Santa hat, pirate hat, etc.)
- **Buddy evolution:** The buddy changes appearance at certain levels (gets armor, grows bigger)
- **Leaderboard:** If multiple people at HypeHype use ClaudeStation, add a shared leaderboard
- **Boss mode:** Every 10 levels, a special harder buddy appears (themed as different AI models)
- **Idle earnings while Claude works:** Even without clicking, earn a base token rate while Claude is actively running

## Known Issues / TODOs for Building

1. **The .xcodeproj is a stub** — either use Package.swift with `swift build` or regenerate proper Xcode project with `swift package generate-xcodeproj` or just create a new Xcode project and add the files
2. **No ANSI stripping yet** — terminal output will have raw escape codes. Need to either strip them for display or use a proper terminal emulator library
3. **PTY is basic** — using `Process` + `Pipe` works but isn't a true pseudo-terminal. For full terminal emulation (colors, cursor movement, alternate screen), consider integrating SwiftTerm (https://github.com/migueldeicaza/SwiftTerm) — but basic Pipe-based I/O should work fine for the MVP
4. **HSplitView** is used for the terminal/queue split — it's available in macOS but somewhat limited. May need custom split view
5. **Input bar keyboard handling** — the Enter vs Shift+Enter distinction needs careful handling in SwiftUI. May need a custom NSViewRepresentable wrapping NSTextField to intercept key events properly
6. **Thread safety** — `outputPipe.fileHandleForReading.readabilityHandler` fires on a background thread but updates `@Published` properties. The current code dispatches to main, but verify no race conditions
7. **Process environment** — Claude Code may need specific env vars (PATH, SHELL, HOME). The current code inherits from ProcessInfo but may need augmentation

## Style Notes

- Monospaced font for terminal output and input bar
- System SF Pro / San Francisco for UI chrome
- Minimal, native macOS look — no custom window chrome
- Status colors: green=running, orange=waiting, gray=idle, red=error
- Queue badge: orange capsule with count
- The app should feel like a natural extension of macOS, not an Electron app

## Testing the Queue

To test the queue system without Claude Code:
1. Make a mock mode that spawns a simple interactive script instead of `claude`
2. The script could echo prompts and wait for input on a timer
3. This lets you test the full queue flow without burning API tokens

Example test script:
```bash
#!/bin/bash
echo "Mock Claude Code v0.0.0"
echo "Ready."
while true; do
    echo -e "\n❯ "
    read -r input
    echo "Processing: $input"
    sleep 2
    echo "Done."
done
```

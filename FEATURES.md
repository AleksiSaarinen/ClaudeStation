# ClaudeStation — Feature Roadmap

Research based on Lovable AI and other AI coding tools. Features adapted for a Claude Code session manager context.

---

## High Impact, Low Effort

### Desktop Notifications
Notify via macOS notifications when a session transitions from `.running` to `.waitingForInput`, especially when the app is in the background. Uses `UNUserNotificationCenter` which is already imported.

### Queue Enhancements
- **Pause/Resume** — Toggle to pause the entire queue across all sessions
- **Inline Editing** — Edit queued messages before they execute
- **Repeat N Times** — Option to repeat a prompt up to N times for iterative refinement

### Suggested Actions
After Claude finishes a task, show 2-3 clickable chips above the input bar suggesting logical next steps based on what just happened:
- "Run tests" after code changes
- "Commit changes" after edits pass
- "Continue" for multi-step tasks
Could parse the last assistant message to determine relevant suggestions.

---

## High Impact, Medium Effort

### Command Palette (Cmd+K)
Quick-access overlay for:
- Switching between sessions
- Launching saved profiles
- Toggling panels (queue, settings)
- Common actions (new session, close session)
Standard in modern dev tools (VS Code, Raycast, Arc).

### Enhanced Plan Mode
The Plan button already exists. Enhance it:
- Parse plan output into a structured card view
- "Approve & Execute" button that queues the implementation
- Save plans to a visible history

### Session Knowledge Panel
Per-session persistent instructions — basically a CLAUDE.md editor built into the app:
- **Session-level** — Instructions specific to one session/project
- **Global** — Instructions that apply to all sessions
- Injected as context when launching Claude Code or prepended to first message

### Condensed Task Cards
Parse Claude's `stream-json` output into collapsible cards instead of raw chat:
- "Edit: src/components/Button.tsx" (collapsed, expandable to show diff)
- "Bash: npm test" (collapsed, expandable to show output)
- "Search: 5 files found" (collapsed, expandable to show list)
Makes long sessions much more scannable and navigable.

---

## Medium Impact, Medium Effort

### Cross-Session References
Type `@session-name` in the input bar to inject context from another running session. Example: "Use the same approach as @altegro for the auth module" pulls relevant output/context from that session.

### @File Autocomplete
When typing `@` in the input bar, show a file picker/autocomplete popup listing files in the working directory. Provides a GUI layer over Claude Code's file reference capability.

### Elevate Questions
When Claude asks a clarifying question, detect it in the output stream and display as a highlighted card with quick-reply buttons. Prevents important questions from getting buried in terminal output.

### Session Organization
As session count grows:
- **Pin** important sessions to top of sidebar
- **Search/Filter** sessions by name
- **Recent** section for recently active sessions
- **Groups/Folders** for organizing related sessions

---

## Nice to Have

### Edit Tracking / Stats
- Messages sent per session
- Total sessions created
- Daily usage streaks
- Token/cost estimates per session
- Model indicator (which Claude model is running)

### Conversation Bookmarks
Snapshot session state at key points. Allow re-sending modified versions of past messages. Branch conversations.

### Stop & Preserve Button
UI button to stop Claude mid-task (instead of Ctrl+C). Visual confirmation of what work was completed before stopping.

### Voice Input
Speech-to-text for the input bar. Hands-free message dictation.

### Session Templates
Pre-configured session setups beyond launch profiles:
- Template with predefined initial messages
- Template with knowledge/instructions baked in
- Shareable templates between users

---

## Already Implemented
- [x] Message Queue (core feature)
- [x] Plan mode toggle
- [x] Session sidebar with status indicators
- [x] Queue badges
- [x] Drag-to-reorder queue
- [x] Send Now / force send
- [x] Launch profiles
- [x] Image attachments
- [x] Pet mascot with state animations
- [x] Friendly tool names in status
- [x] Glass UI effects
- [x] Tab bar with multiple sessions

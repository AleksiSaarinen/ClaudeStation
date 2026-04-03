import SwiftUI

enum DetailTab: String, CaseIterable {
    case terminal = "Terminal"
    case minigame = "Kick the Claude"
}

struct SessionDetailView: View {
    @ObservedObject var session: Session
    @EnvironmentObject var sessionManager: SessionManager
    @State private var inputText: String = ""
    @State private var activeTab: DetailTab = .terminal
    @StateObject private var minigameBridge = MinigameBridge()
    @StateObject private var pasteboardWatcher = PasteboardWatcher()
    @FocusState private var inputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Session header bar with tab switcher
            SessionHeaderBar(session: session, activeTab: $activeTab)

            Divider()

            VStack(spacing: 0) {
                ZStack {
                    // SwiftTerm behind the chat (full size for proper PTY)
                    SwiftTermView(session: session)
                        .id(session.id)
                        .allowsHitTesting(false)

                    // Chat view on top
                    ChatView(session: session)
                }
                .contentShape(Rectangle())
                .onTapGesture { inputFocused = true }

                Divider()

                // Inline queue strip (only visible when messages are queued)
                if !session.messageQueue.isEmpty {
                    InlineQueueStrip(session: session)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Screenshot attachment preview
                if let image = pasteboardWatcher.pendingImage {
                    AttachmentPreview(image: image) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            pasteboardWatcher.clear()
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Input bar
                InputBar(
                    inputText: $inputText,
                    inputFocused: $inputFocused,
                    session: session,
                    hasAttachment: pasteboardWatcher.pendingImagePath != nil,
                    onSend: {
                        guard !inputText.isEmpty || pasteboardWatcher.pendingImagePath != nil else { return }
                        // Build message with optional image path
                        var message = inputText
                        if let path = pasteboardWatcher.pendingImagePath {
                            let prefix = message.isEmpty ? "" : "\n"
                            message += "\(prefix)[Image: \(path)]"
                            pasteboardWatcher.clear()
                        }
                        if session.status == .waitingForInput || session.status == .idle {
                            sessionManager.sendImmediately(message, to: session)
                        } else {
                            sessionManager.queueMessage(message, for: session)
                        }
                        inputText = ""
                    },
                    onForceQueue: {
                        guard !inputText.isEmpty else { return }
                        sessionManager.queueMessage(inputText, for: session)
                        inputText = ""
                    }
                )
            }
            .animation(.easeInOut(duration: 0.25), value: session.messageQueue.count)
            .animation(.easeInOut(duration: 0.2), value: pasteboardWatcher.pendingImage != nil)
        }
        .onAppear {
            inputFocused = true
            pasteboardWatcher.startWatching()
        }
        .onDisappear { pasteboardWatcher.stopWatching() }
        // Bridge session status changes to the minigame
        .onChange(of: session.status) { oldStatus, newStatus in
            minigameBridge.sessionStatusChanged(newStatus.rawValue)
            
            // Reward tokens when Claude finishes a task
            if oldStatus == .running && newStatus == .waitingForInput {
                minigameBridge.taskCompleted(durationSeconds: 30) // TODO: track actual duration
            }
            if oldStatus == .waitingForInput && newStatus == .running {
                minigameBridge.taskStarted()
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    activeTab = activeTab == .terminal ? .minigame : .terminal
                } label: {
                    Label(
                        activeTab == .terminal ? "Play" : "Terminal",
                        systemImage: activeTab == .terminal ? "gamecontroller" : "terminal"
                    )
                }
                .help("Toggle minigame (Cmd+G)")
                .keyboardShortcut("g", modifiers: .command)
            }
            
            ToolbarItem(placement: .automatic) {
                // Stop running process
                if session.status == .running {
                    Button {
                        TerminalService.shared.terminate(session: session)
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .tint(.red)
                }
            }
        }
    }
}

// MARK: - Session Header

struct SessionHeaderBar: View {
    @ObservedObject var session: Session
    @Binding var activeTab: DetailTab

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(session.workingDirectory)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer()

            Text(session.status.rawValue)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .animation(.easeInOut(duration: 0.3), value: session.status)
    }
    
    var statusColor: Color {
        switch session.status {
        case .idle: return .gray
        case .running: return .green
        case .waitingForInput: return .orange
        case .error: return .red
        }
    }
}

// MARK: - Terminal Output

// MARK: - Input Bar

// MARK: - Attachment Preview

struct AttachmentPreview: View {
    let image: NSImage
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Screenshot")
                    .font(.caption.bold())
                Text("\(Int(image.size.width))x\(Int(image.size.height))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove attachment")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

struct InputBar: View {
    @Binding var inputText: String
    var inputFocused: FocusState<Bool>.Binding
    @ObservedObject var session: Session
    var hasAttachment: Bool = false
    var onSend: () -> Void
    var onForceQueue: () -> Void

    private var isReady: Bool {
        session.status == .waitingForInput || session.status == .idle
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .foregroundStyle(isReady ? .green : .orange)
                .font(.system(.body, design: .monospaced).bold())

            TextField("Message to Claude...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .focused(inputFocused)
                .onSubmit {
                    onSend()
                }

            // Smart send button — sends if ready, queues if busy
            Button(action: onSend) {
                Image(systemName: isReady ? "paperplane.fill" : "tray.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .tint(isReady ? .blue : .orange)
            .controlSize(.small)
            .help(isReady ? "Send (Enter)" : "Queue (Enter)")
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

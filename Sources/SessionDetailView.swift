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
    @State private var showFilePicker = false
    @StateObject private var minigameBridge = MinigameBridge()
    @StateObject private var pasteboardWatcher = PasteboardWatcher()
    @FocusState private var inputFocused: Bool
    @State private var taskStartTime: Date?
    
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
                    },
                    onAttach: {
                        showFilePicker = true
                    }
                )
                .fileImporter(
                    isPresented: $showFilePicker,
                    allowedContentTypes: [.image, .plainText, .sourceCode, .json, .data],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        if url.startAccessingSecurityScopedResource() {
                            defer { url.stopAccessingSecurityScopedResource() }
                            // Copy to temp location and attach
                            let tempPath = NSTemporaryDirectory() + "claudestation_\(url.lastPathComponent)"
                            try? FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: tempPath))
                            if let image = NSImage(contentsOf: url) {
                                pasteboardWatcher.pendingImage = image
                                pasteboardWatcher.pendingImagePath = tempPath
                            } else {
                                // Non-image file — add path to input
                                inputText += (inputText.isEmpty ? "" : "\n") + "[File: \(tempPath)]"
                            }
                        }
                    }
                }
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
            
            if oldStatus == .waitingForInput && newStatus == .running {
                taskStartTime = Date()
                minigameBridge.taskStarted()
            }
            if oldStatus == .running && newStatus == .waitingForInput {
                let duration = taskStartTime.map { Date().timeIntervalSince($0) } ?? 30
                minigameBridge.taskCompleted(durationSeconds: Int(duration))
                taskStartTime = nil
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings (Cmd+,)")
            }

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
    @Environment(\.theme) var theme

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(session.status == .running ? theme.accent : theme.successDot)
                .frame(width: 6, height: 6)

            Text(session.workingDirectory)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(theme.chromeText)
                .lineLimit(1)

            Spacer()

            Text(session.status.rawValue)
                .font(.caption2)
                .foregroundStyle(theme.chromeText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(theme.chromeBar)
        .animation(.easeInOut(duration: 0.3), value: session.status)
    }
}

// MARK: - Terminal Output

// MARK: - Input Bar

// MARK: - Attachment Preview

struct AttachmentPreview: View {
    let image: NSImage
    var onRemove: () -> Void
    @Environment(\.theme) var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(theme.chromeBorder, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Screenshot")
                    .font(.caption.bold())
                    .foregroundStyle(theme.chromeText)
                Text("\(Int(image.size.width))x\(Int(image.size.height))")
                    .font(.caption2)
                    .foregroundStyle(theme.mutedText)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(theme.mutedText)
            }
            .buttonStyle(.borderless)
            .help("Remove attachment")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(theme.chromeBar)
    }
}

struct InputBar: View {
    @Binding var inputText: String
    var inputFocused: FocusState<Bool>.Binding
    @ObservedObject var session: Session
    var hasAttachment: Bool = false
    var onSend: () -> Void
    var onForceQueue: () -> Void
    var onAttach: () -> Void = {}
    @Environment(\.theme) var theme
    @State private var planMode = false

    private var isReady: Bool {
        session.status == .waitingForInput || session.status == .idle
    }

    var body: some View {
        VStack(spacing: 0) {
            // Input field in rounded container
            HStack(alignment: .center, spacing: 8) {
                // Plus button for attachments
                Button(action: onAttach) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.mutedText)
                        .frame(width: 28, height: 28)
                        .background(theme.toolCardBg)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(theme.toolCardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Attach file")

                // Text field
                TextField("Message to Claude...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(theme.monoFont)
                    .foregroundStyle(theme.assistantText)
                    .focused(inputFocused)
                    .lineLimit(1...6)
                    .onSubmit { onSend() }

                // Right side buttons
                HStack(spacing: 6) {
                    // Plan mode toggle
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { planMode.toggle() }
                    } label: {
                        Text("Plan")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(planMode ? theme.userBubbleText : theme.mutedText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(planMode ? theme.accent : theme.toolCardBg)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(planMode ? theme.accent : theme.toolCardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Toggle plan mode")

                    // Send button
                    Button(action: onSend) {
                        Image(systemName: isReady ? "arrow.up" : "tray.and.arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(inputText.isEmpty && !hasAttachment ? theme.mutedText : .white)
                            .frame(width: 28, height: 28)
                            .background(inputText.isEmpty && !hasAttachment ? theme.toolCardBg : theme.accent)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.isEmpty && !hasAttachment)
                    .help(isReady ? "Send (Enter)" : "Queue (Enter)")
                    .keyboardShortcut(.return, modifiers: [])
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(theme.inputBg)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(theme.inputBorder, lineWidth: 1)
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.chatBg)
    }
}

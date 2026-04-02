import SwiftUI

enum DetailTab: String, CaseIterable {
    case terminal = "Terminal"
    case minigame = "Kick the Claude"
}

struct SessionDetailView: View {
    @ObservedObject var session: Session
    @EnvironmentObject var sessionManager: SessionManager
    @State private var inputText: String = ""
    @State private var showQueue: Bool = true
    @State private var activeTab: DetailTab = .terminal
    @StateObject private var minigameBridge = MinigameBridge()
    @FocusState private var inputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Session header bar with tab switcher
            SessionHeaderBar(session: session, activeTab: $activeTab)
            
            Divider()
            
            HSplitView {
                // Main content area — terminal or minigame
                VStack(spacing: 0) {
                    switch activeTab {
                    case .terminal:
                        TerminalOutputView(session: session)
                    case .minigame:
                        MinigameView(bridge: minigameBridge)
                    }
                    
                    Divider()
                    
                    // Input bar (always visible — you can queue messages while playing)
                    InputBar(
                        inputText: $inputText,
                        inputFocused: $inputFocused,
                        onSendImmediate: {
                            // Allow empty sends — acts as pressing Enter in the terminal
                            sessionManager.sendImmediately(inputText, to: session)
                            inputText = ""
                        },
                        onSendToQueue: {
                            guard !inputText.isEmpty else { return }
                            sessionManager.queueMessage(inputText, for: session)
                            inputText = ""
                        }
                    )
                }
                
                // Message queue panel
                if showQueue {
                    MessageQueuePanel(session: session)
                        .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)
                }
            }
        }
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
                Toggle(isOn: $showQueue) {
                    Label("Queue", systemImage: "tray.full")
                }
                .help("Toggle message queue panel")
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
                Button {
                    if session.process == nil || session.status == .idle {
                        sessionManager.launchSession(session)
                    } else {
                        TerminalService.shared.terminate(session: session)
                    }
                } label: {
                    Label(
                        session.status == .idle ? "Launch" : "Stop",
                        systemImage: session.status == .idle ? "play.fill" : "stop.fill"
                    )
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
        HStack {
            // Working directory
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(session.workingDirectory)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            // Tab switcher
            Picker("View", selection: $activeTab) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            
            Spacer()
            
            // Status pill
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(session.status.rawValue)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
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

struct TerminalOutputView: View {
    @ObservedObject var session: Session
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(session.outputBuffer.isEmpty ? "Session not started. Press Launch to begin." : session.outputBuffer)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
                    .id("output-bottom")
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: session.outputBuffer) { _, _ in
                withAnimation {
                    proxy.scrollTo("output-bottom", anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Input Bar

struct InputBar: View {
    @Binding var inputText: String
    var inputFocused: FocusState<Bool>.Binding
    var onSendImmediate: () -> Void
    var onSendToQueue: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .foregroundStyle(.orange)
                .font(.system(.body, design: .monospaced).bold())
            
            TextField("Message to Claude...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .focused(inputFocused)
                .onSubmit {
                    onSendToQueue()
                }
            
            // Queue button (default action)
            Button {
                onSendToQueue()
            } label: {
                Label("Queue", systemImage: "tray.and.arrow.down")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .help("Add to queue (Enter)")
            .keyboardShortcut(.return, modifiers: [])
            
            // Send immediately button
            Button {
                onSendImmediate()
            } label: {
                Label("Send Now", systemImage: "paperplane.fill")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            .help("Send immediately (⇧Enter)")
            .keyboardShortcut(.return, modifiers: .shift)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

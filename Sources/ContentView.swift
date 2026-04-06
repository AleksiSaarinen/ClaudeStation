import SwiftUI
import UniformTypeIdentifiers

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.theme) var theme
    @Environment(\.openWindow) var openWindow
    @State private var showCommandPalette = false
    @State private var draggingSessionId: UUID?
    @State private var tearOffTargeted = false

    var body: some View {
        ZStack {
            theme.chatBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                TabBar(draggingSessionId: $draggingSessionId)

                // Content area — also a drop target for tear-off
                ZStack {
                    if let session = sessionManager.activeSession {
                        SessionDetailView(session: session)
                            .id(session.id)
                    } else {
                        VStack {
                            Spacer()
                            Text("No session")
                                .foregroundStyle(theme.mutedText)
                            Spacer()
                        }
                    }

                    // Tear-off drop zone — transparent overlay that catches tab drags
                    // This sits above SessionDetailView so its onDrop fires first for .plainText
                    if draggingSessionId != nil {
                        Color.clear
                            .contentShape(Rectangle())
                            .onDrop(of: [.plainText], isTargeted: $tearOffTargeted) { _ in
                                guard let sessionId = draggingSessionId,
                                      sessionManager.tabBarSessions.count > 1 else {
                                    draggingSessionId = nil
                                    return false
                                }
                                sessionManager.detachSession(sessionId)
                                openWindow(id: "detached-session", value: sessionId)
                                draggingSessionId = nil
                                return true
                            }
                    }

                    // Tear-off indicator
                    if tearOffTargeted && draggingSessionId != nil && sessionManager.tabBarSessions.count > 1 {
                        VStack {
                            HStack(spacing: 6) {
                                Image(systemName: "macwindow.badge.plus")
                                Text("Release to open in new window")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .background(theme.accent.opacity(0.3))
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
                            .padding(.top, 60)
                            Spacer()
                        }
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .animation(.easeOut(duration: 0.15), value: tearOffTargeted)
            }

            CommandPalette(isPresented: $showCommandPalette)
                .animation(.easeOut(duration: 0.15), value: showCommandPalette)
        }
        .keyboardShortcut(KeyEquivalent("k"), modifiers: .command, action: {
            showCommandPalette.toggle()
        })
        .onChange(of: draggingSessionId) { _, newValue in
            if newValue != nil { pollForDragEnd() }
        }
        .background(WindowFrameSaver(name: "MainWindow"))
    }
}

extension ContentView {
    /// Poll during a tab drag to detect when the mouse is released outside the window.
    /// If the drag ends outside the window, tear off the tab into a new window.
    func pollForDragEnd() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let sessionId = draggingSessionId else { return }
            if NSEvent.pressedMouseButtons == 0 {
                // Mouse released — drag ended without any drop delegate handling it
                draggingSessionId = nil
                if let window = NSApp.keyWindow {
                    let mouse = NSEvent.mouseLocation
                    if !window.frame.contains(mouse) && sessionManager.tabBarSessions.count > 1 {
                        sessionManager.detachSession(sessionId)
                        openWindow(id: "detached-session", value: sessionId)
                    }
                }
            } else {
                pollForDragEnd() // still dragging — check again
            }
        }
    }
}

// MARK: - Window Frame Persistence

/// Sets the window's frameAutosaveName so AppKit remembers position and size across launches.
struct WindowFrameSaver: NSViewRepresentable {
    let name: String
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.setFrameAutosaveName(name)
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// Keyboard shortcut extension for views
extension View {
    func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers, action: @escaping () -> Void) -> some View {
        self.background(
            Button("") { action() }
                .keyboardShortcut(key, modifiers: modifiers)
                .opacity(0)
                .frame(width: 0, height: 0)
        )
    }
}

// MARK: - Tab Bar

struct TabBar: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.theme) var theme
    @Binding var draggingSessionId: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 1) {
                ForEach(sessionManager.tabBarSessions) { session in
                    tabItem(for: session)
                }

                // + button hugs the last tab (inside the ScrollView, not pushed right)
                Button {
                    sessionManager.createSessionWithPicker()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.chromeText)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
                .help("New Session (⌘T)")
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
        }
        .frame(height: 36)
        .background(theme.chromeBar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.chromeBorder).frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func tabItem(for session: Session) -> some View {
        let isActive = session.id == sessionManager.activeSessionId
        let provider = NSItemProvider(object: session.id.uuidString as NSString)
        SessionTab(
            session: session,
            draggingSessionId: $draggingSessionId,
            isActive: isActive
        )
        .onTapGesture {
            sessionManager.activeSessionId = session.id
        }
        .onDrag {
            draggingSessionId = session.id
            return provider
        }
        .onDrop(of: [.plainText], delegate: TabDropDelegate(
            targetSession: session,
            draggingSessionId: $draggingSessionId,
            sessionManager: sessionManager
        ))
    }
}

// MARK: - Session Tab

struct SessionTab: View {
    @ObservedObject var session: Session
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.theme) var theme
    @Environment(\.openWindow) var openWindow
    @State private var isEditing = false
    @State private var editName = ""
    @State private var hovering = false
    @Binding var draggingSessionId: UUID?

    let isActive: Bool

    private var isDragging: Bool { draggingSessionId == session.id }

    var body: some View {
        HStack(spacing: 5) {
            // Status dot
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)

            // Name (editable on double-click)
            if isEditing {
                TextField("Name", text: $editName, onCommit: {
                    session.name = editName
                    isEditing = false
                })
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .monospaced))
                .frame(minWidth: 40, maxWidth: 140)
                .onExitCommand { isEditing = false }
            } else {
                Text(session.displayName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isActive ? theme.assistantText : theme.chromeText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 40, maxWidth: 140)
                    .onTapGesture(count: 2) {
                        editName = session.name.isEmpty ? session.displayName : session.name
                        isEditing = true
                    }
            }

            // Queue badge
            if !session.messageQueue.isEmpty {
                Text("\(session.messageQueue.count)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(theme.accent.opacity(0.2))
                    .clipShape(Capsule())
            }

            // Close button — visible on hover or when active, with hover highlight
            if hovering || isActive {
                Button {
                    sessionManager.closeSession(session.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.mutedText)
                        .frame(width: 16, height: 16)
                        .background(
                            Circle()
                                .fill(theme.chromeBorder.opacity(hovering ? 0.5 : 0))
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .disabled(sessionManager.sessions.count <= 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? theme.chatBg : (hovering ? theme.chromeBorder.opacity(0.25) : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isActive ? theme.chromeBorder : .clear, lineWidth: 0.5)
        )
        .opacity(isDragging ? 0.35 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .animation(.easeInOut(duration: 0.15), value: isActive)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Rename...") {
                editName = session.name.isEmpty ? session.displayName : session.name
                isEditing = true
            }
            Button("Duplicate") {
                sessionManager.createSession(name: session.name, workingDirectory: session.workingDirectory)
            }
            Divider()
            if sessionManager.tabBarSessions.count > 1 {
                Button("Move to New Window") {
                    sessionManager.detachSession(session.id)
                    openWindow(id: "detached-session", value: session.id)
                }
                Divider()
            }
            Button("Close", role: .destructive) {
                sessionManager.closeSession(session.id)
            }
            .disabled(sessionManager.sessions.count <= 1)
        }
    }

    private var dotColor: Color {
        switch session.status {
        case .running: return theme.accent
        case .waitingForInput: return theme.successDot
        case .error: return .red
        case .idle: return theme.mutedText
        }
    }
}

// MARK: - Tab Drop Delegate (reordering)

struct TabDropDelegate: DropDelegate {
    let targetSession: Session
    @Binding var draggingSessionId: UUID?
    let sessionManager: SessionManager

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingSessionId = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragging = draggingSessionId,
              dragging != targetSession.id,
              let fromIdx = sessionManager.sessions.firstIndex(where: { $0.id == dragging }),
              let toIdx = sessionManager.sessions.firstIndex(where: { $0.id == targetSession.id })
        else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            sessionManager.sessions.move(
                fromOffsets: IndexSet(integer: fromIdx),
                toOffset: toIdx > fromIdx ? toIdx + 1 : toIdx
            )
        }
    }
}

// MARK: - Detached Session Window

struct DetachedSessionWindow: View {
    let sessionId: UUID
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.theme) var theme

    private var session: Session? {
        sessionManager.sessions.first { $0.id == sessionId }
    }

    var body: some View {
        if let session {
            VStack(spacing: 0) {
                // Compact header with session info + return button
                HStack(spacing: 8) {
                    Circle()
                        .fill(dotColor(for: session))
                        .frame(width: 6, height: 6)

                    Text(session.displayName)
                        .font(.system(.caption, design: .monospaced).bold())
                        .foregroundStyle(theme.chromeText)
                        .lineLimit(1)

                    Text("·").foregroundStyle(theme.mutedText)

                    Text(session.workingDirectory)
                        .font(.caption2)
                        .foregroundStyle(theme.mutedText)
                        .lineLimit(1)
                        .truncationMode(.head)

                    Spacer()

                    Button {
                        sessionManager.reattachSession(sessionId)
                        NSApp.keyWindow?.close()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.stack.badge.plus")
                                .font(.caption2)
                            Text("Return to Main")
                                .font(.caption2)
                        }
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(theme.accent.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(theme.chromeBar)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(theme.chromeBorder).frame(height: 0.5)
                }

                SessionDetailView(session: session)
                    .id(session.id)
            }
            .background(theme.chatBackground)
            .onDisappear {
                // Window closed via traffic light → reattach session
                if sessionManager.detachedSessionIds.contains(sessionId) {
                    sessionManager.reattachSession(sessionId)
                }
            }
        } else {
            VStack {
                Text("Session not found")
                    .foregroundStyle(theme.mutedText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.chatBackground)
        }
    }

    private func dotColor(for session: Session) -> Color {
        switch session.status {
        case .running: return theme.accent
        case .waitingForInput: return theme.successDot
        case .error: return .red
        case .idle: return theme.mutedText
        }
    }
}

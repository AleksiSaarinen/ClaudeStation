import SwiftUI

struct ContentView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.theme) var theme
    @State private var showCommandPalette = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TabBar()
                    .environmentObject(sessionManager)

                if let session = sessionManager.activeSession {
                    SessionDetailView(session: session)
                        .id(session.id)
                } else {
                    Spacer()
                    Text("No session")
                        .foregroundStyle(theme.mutedText)
                    Spacer()
                }
            }

            CommandPalette(isPresented: $showCommandPalette)
                .animation(.easeOut(duration: 0.15), value: showCommandPalette)
        }
        .keyboardShortcut(KeyEquivalent("k"), modifiers: .command, action: {
            showCommandPalette.toggle()
        })
    }
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

    var body: some View {
        HStack(spacing: 0) {
            // Tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(sessionManager.sessions) { session in
                        SessionTab(
                            session: session,
                            isActive: session.id == sessionManager.activeSessionId
                        )
                        .onTapGesture {
                            sessionManager.activeSessionId = session.id
                        }
                    }
                }
                .padding(.leading, 4)
            }

            Spacer(minLength: 0)

            // New tab button
            Button {
                sessionManager.createSession()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.chromeText)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .help("New Session (Cmd+T)")
        }
        .frame(height: 32)
        .background(theme.chromeBar)
    }
}

// MARK: - Session Tab

struct SessionTab: View {
    @ObservedObject var session: Session
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.theme) var theme
    @State private var isEditing = false
    @State private var editName = ""
    @State private var hovering = false

    let isActive: Bool

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
                .frame(maxWidth: 120)
                .onExitCommand { isEditing = false }
            } else {
                Text(session.displayName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isActive ? theme.assistantText : theme.chromeText)
                    .lineLimit(1)
                    .frame(maxWidth: 120)
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

            // Close button (visible on hover or active)
            if (hovering || isActive) && sessionManager.sessions.count > 1 {
                Button {
                    sessionManager.closeSession(session.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.mutedText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? theme.chatBg : theme.chromeBar)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isActive ? theme.chromeBorder : .clear, lineWidth: 0.5)
        )
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

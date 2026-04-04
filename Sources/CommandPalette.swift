import SwiftUI

struct CommandPaletteAction: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String?
    let action: () -> Void
}

struct CommandPalette: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.theme) var theme
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        if isPresented {
            ZStack {
                // Dimmed background
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { isPresented = false }

                // Palette
                VStack(spacing: 0) {
                    // Search field
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(theme.mutedText)
                        TextField("Type a command...", text: $query)
                            .textFieldStyle(.plain)
                            .font(theme.monoFont)
                            .foregroundStyle(theme.assistantText)
                            .focused($focused)
                            .onSubmit {
                                if let first = filteredActions.first {
                                    first.action()
                                    isPresented = false
                                }
                            }
                    }
                    .padding(12)

                    Divider().background(theme.chromeBorder)

                    // Results
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(filteredActions) { action in
                                Button {
                                    action.action()
                                    isPresented = false
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: action.icon)
                                            .font(.system(size: 12))
                                            .foregroundStyle(theme.accent)
                                            .frame(width: 20)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(action.title)
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(theme.assistantText)
                                            if let sub = action.subtitle {
                                                Text(sub)
                                                    .font(.system(.caption2, design: .monospaced))
                                                    .foregroundStyle(theme.mutedText)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 250)
                }
                .background(theme.assistantBubble)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(theme.chromeBorder, lineWidth: 1)
                )
                .frame(width: 400)
                .shadow(color: .black.opacity(0.3), radius: 20)
                .offset(y: -60)
            }
            .transition(.opacity)
            .onAppear {
                query = ""
                focused = true
            }
            .onExitCommand { isPresented = false }
        }
    }

    private var allActions: [CommandPaletteAction] {
        var actions: [CommandPaletteAction] = [
            CommandPaletteAction(icon: "plus", title: "New Session", subtitle: "Cmd+T") {
                sessionManager.createSession()
            },
            CommandPaletteAction(icon: "folder", title: "Change Directory", subtitle: nil) {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                if panel.runModal() == .OK, let url = panel.url,
                   let session = sessionManager.activeSession {
                    session.workingDirectory = url.path
                    session.claudeSessionId = nil
                }
            },
            CommandPaletteAction(icon: "trash", title: "Clear Chat", subtitle: nil) {
                sessionManager.activeSession?.chatMessages.removeAll()
            },
            CommandPaletteAction(icon: "gearshape", title: "Settings", subtitle: "Cmd+,") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            },
        ]

        // Add session switching
        for (i, session) in sessionManager.sessions.enumerated() {
            let shortcut = i < 9 ? "Cmd+\(i + 1)" : nil
            actions.append(CommandPaletteAction(
                icon: "terminal",
                title: "Switch to: \(session.displayName)",
                subtitle: shortcut
            ) {
                sessionManager.activeSessionId = session.id
            })
        }

        return actions
    }

    private var filteredActions: [CommandPaletteAction] {
        if query.isEmpty { return allActions }
        return allActions.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            ($0.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
}

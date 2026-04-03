import SwiftUI

struct ContentView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .detailOnly

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            List(selection: $sessionManager.activeSessionId) {
                Section("Sessions") {
                    ForEach(sessionManager.sessions) { session in
                        SessionRow(session: session)
                            .tag(session.id)
                            .contextMenu {
                                Button("Duplicate") {
                                    sessionManager.createSession(
                                        name: session.name,
                                        workingDirectory: session.workingDirectory
                                    )
                                }
                                Divider()
                                Button("Close", role: .destructive) {
                                    sessionManager.closeSession(session.id)
                                }
                                .disabled(sessionManager.sessions.count <= 1)
                            }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200)
            .toolbar {
                ToolbarItem {
                    Button {
                        sessionManager.createSession()
                    } label: {
                        Label("New Session", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let session = sessionManager.activeSession {
                SessionDetailView(session: session)
            } else {
                Text("No session selected")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Session Row

struct SessionRow: View {
    @ObservedObject var session: Session

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayName)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)

                Text(session.workingDirectory)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !session.messageQueue.isEmpty {
                Text("\(session.messageQueue.count)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.orange.opacity(0.2))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
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

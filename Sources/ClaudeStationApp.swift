import SwiftUI

@main
struct ClaudeStationApp: App {
    @StateObject private var sessionManager = SessionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
                .frame(minWidth: 900, minHeight: 600)
                .onOpenURL { url in
                    handleURL(url)
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Session") {
                    sessionManager.createSession()
                }
                .keyboardShortcut("t", modifiers: .command)

                Divider()

                ForEach(Array(sessionManager.sessions.enumerated()), id: \.element.id) { index, session in
                    if index < 9 {
                        Button("Switch to: \(session.displayName)") {
                            sessionManager.activeSessionId = session.id
                        }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    }
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(sessionManager)
        }
    }

    // MARK: - URL Scheme Handler
    // Usage: open "claudestation://launch"
    //        open "claudestation://send?text=hello"
    //        open "claudestation://status"
    //        open "claudestation://new"
    //        open "claudestation://switch?index=2"

    private func handleURL(_ url: URL) {
        guard url.scheme == "claudestation" else { return }
        let command = url.host ?? ""
        let params = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.reduce(into: [String: String]()) { $0[$1.name] = $1.value } ?? [:]

        switch command {
        case "launch":
            if let session = sessionManager.activeSession {
                if session.process == nil || session.status == .idle {
                    sessionManager.launchSession(session)
                }
            }

        case "send":
            if let text = params["text"], let session = sessionManager.activeSession {
                sessionManager.sendImmediately(text, to: session)
            }

        case "enter":
            // Send empty Enter (for accepting prompts)
            if let session = sessionManager.activeSession {
                sessionManager.sendImmediately("", to: session)
            }

        case "new":
            let dir = params["dir"]
            sessionManager.createSession(workingDirectory: dir)

        case "switch":
            if let indexStr = params["index"], let index = Int(indexStr),
               index > 0, index <= sessionManager.sessions.count {
                sessionManager.activeSessionId = sessionManager.sessions[index - 1].id
            }

        case "status":
            // Write status to a temp file for reading
            writeStatus()

        default:
            break
        }
    }

    private func writeStatus() {
        guard let session = sessionManager.activeSession else { return }
        var info = [String: Any]()
        info["status"] = session.status.rawValue
        info["sessionCount"] = sessionManager.sessions.count
        info["messageCount"] = session.chatMessages.count
        info["queueCount"] = session.messageQueue.count
        info["workingDirectory"] = session.workingDirectory

        // Include last few chat messages
        let recentMessages = session.chatMessages.suffix(5).map { msg -> [String: String] in
            ["role": msg.role == .user ? "user" : "assistant", "content": String(msg.content.prefix(200))]
        }
        info["recentMessages"] = recentMessages

        if let data = try? JSONSerialization.data(withJSONObject: info, options: .prettyPrinted),
           let json = String(data: data, encoding: .utf8) {
            try? json.write(toFile: "/tmp/claudestation_status.json", atomically: true, encoding: .utf8)
        }
    }
}

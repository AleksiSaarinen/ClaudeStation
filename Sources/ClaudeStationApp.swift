import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    var sessionManager: SessionManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Strip tiling state from saved window frame to prevent macOS
        // from stretching the window on restore
        let key = "NSWindow Frame main"
        if let saved = UserDefaults.standard.string(forKey: key),
           let braceRange = saved.range(of: " {") {
            let cleaned = String(saved[saved.startIndex..<braceRange.lowerBound])
            UserDefaults.standard.set(cleaned, forKey: key)
        }

        // Apply selected cursor pack
        let cursorPack = UserDefaults.standard.string(forKey: "selectedCursorPack") ?? "system"
        CursorManager.applyPack(cursorPack)
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let newSession = NSMenuItem(title: "New Session", action: #selector(newSession), keyEquivalent: "")
        newSession.target = self
        menu.addItem(newSession)
        return menu
    }

    @objc func newSession() {
        sessionManager?.createSessionWithPicker()
    }
}

@main
struct ClaudeStationApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var sessionManager = SessionManager()

    init() {}
    @AppStorage("selectedTheme") private var selectedThemeId = "midnight"
    @AppStorage("customMonoFont") private var customMonoFont = ""

    var body: some Scene {
        // Single-instance Window — prevents URL scheme calls from spawning duplicates
        Window("ClaudeStation", id: "main") {
            let activeTheme = Theme.byId(selectedThemeId).withFonts(mono: customMonoFont.isEmpty ? nil : customMonoFont, ui: nil)
            ContentView()
                .environmentObject(sessionManager)
                .onAppear {
                    appDelegate.sessionManager = sessionManager
                    UsageMonitor.shared.startMonitoring(interval: 120)
                }
                .environment(\.theme, activeTheme)
                .id(selectedThemeId + customMonoFont)
                .frame(minWidth: 350, minHeight: 300)
                .onOpenURL { url in
                    handleURL(url)
                }
        }
        .defaultSize(width: 600, height: 600)
        .commands {
            // Replace default "New Window" (Cmd+N) with our "New Session"
            CommandGroup(replacing: .newItem) {
                Button("New Session") {
                    sessionManager.createSessionWithPicker()
                }
                .keyboardShortcut("t", modifiers: .command)

                Divider()

                ForEach(Array(sessionManager.tabBarSessions.enumerated()), id: \.element.id) { index, session in
                    if index < 9 {
                        Button("Switch to: \(session.displayName)") {
                            sessionManager.activeSessionId = session.id
                        }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    }
                }
            }
        }

        // Detached session windows (tear-off tabs)
        WindowGroup(id: "detached-session", for: UUID.self) { $sessionId in
            if let sessionId {
                let activeTheme = Theme.byId(selectedThemeId).withFonts(mono: customMonoFont.isEmpty ? nil : customMonoFont, ui: nil)
                DetachedSessionWindow(sessionId: sessionId)
                    .environmentObject(sessionManager)
                    .environment(\.theme, activeTheme)
                    .frame(minWidth: 350, minHeight: 300)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(sessionManager)
                .environment(\.theme, Theme.byId(selectedThemeId).withFonts(mono: customMonoFont.isEmpty ? nil : customMonoFont, ui: nil))
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
            // No-op in stream-json mode (sessions are always ready)
            break

        case "send":
            if let text = params["text"], let session = sessionManager.activeSession {
                if session.status == .waitingForInput || session.status == .idle {
                    sessionManager.sendImmediately(text, to: session)
                } else {
                    sessionManager.queueMessage(text, for: session)
                }
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
            ["role": msg.role == .user ? "user" : "assistant", "content": msg.content]
        }
        info["recentMessages"] = recentMessages

        if let data = try? JSONSerialization.data(withJSONObject: info, options: .prettyPrinted),
           let json = String(data: data, encoding: .utf8) {
            try? json.write(toFile: "/tmp/claudestation_status.json", atomically: true, encoding: .utf8)
        }
    }
}

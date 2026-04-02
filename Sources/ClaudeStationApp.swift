import SwiftUI

@main
struct ClaudeStationApp: App {
    @StateObject private var sessionManager = SessionManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
                .frame(minWidth: 900, minHeight: 600)
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
}

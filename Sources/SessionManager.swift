import Foundation
import Combine
import SwiftUI

/// Manages all Claude Code sessions
class SessionManager: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var activeSessionId: UUID?
    
    let settings = AppSettings.shared
    
    var activeSession: Session? {
        sessions.first { $0.id == activeSessionId }
    }
    
    private var saveDebounce: DispatchWorkItem?

    private var saveObserver: Any?

    init() {
        // Restore saved sessions or start fresh
        let restored = SessionPersistence.load()
        if restored.isEmpty {
            createSession()
        } else {
            sessions = restored
            activeSessionId = sessions.first?.id
        }

        // Listen for save triggers from TerminalService
        saveObserver = NotificationCenter.default.addObserver(
            forName: .init("ClaudeStationSave"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.scheduleSave()
        }
    }

    /// Save sessions to disk (debounced)
    func scheduleSave() {
        saveDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            SessionPersistence.save(sessions: self.sessions)
        }
        saveDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }
    
    // MARK: - Session Lifecycle
    
    @discardableResult
    func createSession(name: String = "", workingDirectory: String? = nil) -> Session {
        let rawDir = workingDirectory ?? settings.defaultWorkingDirectory
        let dir = (rawDir as NSString).expandingTildeInPath
        // Validate directory exists, fall back to home
        let validDir = FileManager.default.fileExists(atPath: dir) ? rawDir : "~"
        let trimmedName = String(name.prefix(50))
        let session = Session(name: trimmedName, workingDirectory: validDir)
        sessions.append(session)
        activeSessionId = session.id
        // No PTY launch needed — stream-json mode spawns per message
        session.status = .waitingForInput
        scheduleSave()
        return session
    }
    
    func createSessionFromProfile(_ profile: LaunchProfile) -> Session {
        let session = createSession(name: profile.name, workingDirectory: profile.workingDirectory)
        // Profile flags will be applied when launching
        return session
    }
    
    func closeSession(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let session = sessions[index]
        
        // Terminate the process if running
        TerminalService.shared.terminate(session: session)
        
        sessions.remove(at: index)
        
        // Switch to another session if we closed the active one
        if activeSessionId == id {
            activeSessionId = sessions.last?.id
        }
        
        // Always keep at least one session
        if sessions.isEmpty {
            createSession()
        }
        scheduleSave()
    }
    
    // MARK: - Message Queue
    
    /// Send a message — TerminalService handles queueing if busy
    func sendImmediately(_ text: String, to session: Session) {
        TerminalService.shared.send(text: text, to: session)
        scheduleSave()
    }

    /// Create a session with a folder picker dialog
    func createSessionWithPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose working directory for new session"
        if panel.runModal() == .OK, let url = panel.url {
            createSession(workingDirectory: url.path)
        }
    }

    /// Explicitly queue a message (for force-queue scenarios)
    func queueMessage(_ text: String, for session: Session) {
        session.messageQueue.append(QueuedMessage(text: text))
    }
    
    /// Remove a queued message before it's sent
    func dequeueMessage(_ messageId: UUID, from session: Session) {
        session.messageQueue.removeAll { $0.id == messageId }
    }
    
    /// Reorder queue
    func moveQueuedMessage(from source: IndexSet, to destination: Int, in session: Session) {
        session.messageQueue.move(fromOffsets: source, toOffset: destination)
    }
}
